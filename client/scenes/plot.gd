extends Node2D
## Inside one of the player's plots: 250 × 250 tiles of the biome's ground with its trees, rocks
## and dunes, the railway along the top with the plot's station and, on a mountain plot, its mines.
## The character walks with WSAD or by clicking; clicking a tree, rock or dune walks up to it and
## works it with the tool in hand, and a mine is worked with a pickaxe for ore.
## The station window loads goods from the inventory and sends them by train to other plots.
## A workbench, a furnace or a machine that processes crops (mill, oil press, pickling barrel,
## bakery, field kitchen) from the inventory can be put on a free tile and used there, and so can
## belts and inserters (turned with R) that move items between machines and chests, piles and silos.

## Keyboard actions of this screen: name and keys.
const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"inventory": [KEY_I],
	"station": [KEY_T],
	"tool": [KEY_Q],
	"plant": [KEY_P],
	"cancel": [KEY_ESCAPE],
	"world_map": [KEY_N],
	"garage": [KEY_G],
	"rotate": [KEY_R],
}

const LAYOUT_FILE := "res://art/plot/layout.json"
## Pixels of one tile on screen; a tile is drawn as 2 × 2 m at 32 px per metre, seen at 45°.
const TILE := Vector2(64, 45)
## The character is rendered for the garage at 96 px per metre.
const PLAYER_SCALE := 1.0 / 3.0
const LIGHT := Color(0.78, 0.76, 0.8)
## Tiles per second.
const SPEED := 3.2
## Half the width of the body, in tiles.
const RADIUS := 0.25
## How close (tiles, centre to centre) the player must be to work a tile, and to use the station.
const REACH := 1.75
const STATION_REACH := 2.5
## Tiles are drawn in square chunks around the player.
const CHUNK := 16
const CHUNK_RADIUS := 2
const MIN_ZOOM := 0.5
const MAX_ZOOM := 1.5

## What stands on a tile, as the server numbers it.
const NONE := 0
const TREE := 1
const ROCK := 2
const DUNE := 3
const RAIL := 4
const STATION := 5
const BUSH := 6
const MINE := 7

const SPRITES := {
	TREE: ["tree_0", "tree_1", "tree_2", "tree_3", "tree_4"],
	ROCK: ["rock_0", "rock_1", "rock_2"],
	DUNE: ["dune_0", "dune_1"],
	BUSH: ["bush_0", "bush_1"],
}
const SOLID := [TREE, ROCK, DUNE, STATION, MINE]
## Objects that can be worked: their name, the tool and how the tool is named in "you need a ...".
const WORK := {
	TREE: {"name": "Drzewo", "tool": "tool_axe", "verb": "Zetnij", "need": "siekiery"},
	ROCK: {"name": "Skała", "tool": "tool_pickaxe", "verb": "Rozbij", "need": "kilofa"},
	DUNE: {"name": "Wydma", "tool": "tool_shovel", "verb": "Kop", "need": "łopaty"},
}
const OBJECT_NAMES := {BUSH: "Krzak", STATION: "Stacja kolejowa", MINE: "Kopalnia"}
## What a player can put on a plot from the inventory, and its sprite there; belts are drawn by
## PlotLogistics, flat on the ground.
const PLACED_SPRITES := {
	"furniture_workbench": "workbench", "furniture_furnace": "furnace",
	"furniture_mill": "mill", "furniture_oil_press": "oil_press", "furniture_pickling_barrel": "pickling_barrel",
	"furniture_bakery": "bakery", "furniture_kitchen": "kitchen", "logistics_inserter": "inserter", "logistics_splitter": "splitter",
	"storage_wooden_chest": "wooden_chest", "storage_iron_chest": "iron_chest", "storage_wood_pile": "wood_pile",
	"storage_heap": "heap", "storage_grain_silo": "grain_silo",
}
## Placed objects that open the machine window.
const MACHINES := ["furniture_mill", "furniture_oil_press", "furniture_pickling_barrel", "furniture_bakery", "furniture_kitchen"]
const BELT := "logistics_belt"
const INSERTER := "logistics_inserter"
const SPLITTER := "logistics_splitter"
## Belts, inserters and splitters: turned with R and laid one after another.
const MACHINERY := [BELT, INSERTER, SPLITTER]
const STORAGES := ["storage_wooden_chest", "storage_iron_chest", "storage_wood_pile", "storage_heap", "storage_grain_silo"]
## Where a rotation faces, as players read it: 0 south, 1 east, 2 north, 3 west.
const DIRECTIONS := ["na południe", "na wschód", "na północ", "na zachód"]
const DIRECTION_ARROWS := ["↓", "→", "↑", "←"]
## How often (ms) the belts and inserters are asked for while the plot has any.
const LOGISTICS_POLL := 1000.0
## Crops in the order of the art; the server sends their names and growing times.
const CROPS := ["wheat", "carrot", "cabbage", "corn", "potato", "sunflower"]
## A crop shows as a sprout until this much of its growing time is left, then half grown.
const SPROUT_UNTIL := 0.6
## A planted tree shows as a sapling until this much of its growing time is left, then young;
## grown, it looks like one of the conifers of the forest.
const SAPLING_UNTIL := 0.5
const GROWN_TREES := ["tree_0", "tree_1", "tree_2"]
## Ground texture by biome id (see WorldData).
const FLOORS := {
	2: "forest", 3: "dry_grass", 4: "grass", 5: "sand", 6: "gravel", 7: "tundra",
	8: "snow", 9: "concrete", 10: "dry_grass", 11: "grass",
}
const MINIMAP_COLORS := {
	NONE: Color(0, 0, 0, 0), TREE: Color("#2f5a2a"), ROCK: Color("#8a8580"), DUNE: Color("#c9a25a"),
	RAIL: Color("#4a3a2e"), STATION: Color("#b5663a"), BUSH: Color("#3f6a30"), MINE: Color("#e0b040"),
}
const FIELD_COLOR := Color("#6a4526")

var _layout := {}
var _plot := {}
var _at := Vector2i(-1, -1)
var _size := 250
var _tiles := PackedByteArray()
var _harvest_seconds := 1.5
var _chop_seconds := 5.0
## Seconds of work on the tile being worked.
var _work_seconds := 1.5
var _world_width := 6933
var _biome_names := {}
var _my_plots: Array[Vector2i] = []
var _balance := 0
var _items: Array = []
var _ready_to_play := false
## Tilled tiles: Vector2i → { crop, readyAt } (crop and readyAt null on an empty field).
var _fields := {}
var _crops := {}
var _fertile := false
## Planted trees: Vector2i → readyAt (server milliseconds).
var _trees := {}
## How long a sapling grows on this plot; 0 when nothing can be planted here.
var _tree_grow_seconds := 0.0
## Saplings in the inventory, and whether a click on free ground plants one.
var _saplings := 0
var _planting := false
var _plant_button: Button
## Which crop or tree sprite each drawn field or planted tree shows, to swap it when it grows.
var _stages := {}
var _next_stage_check := 0.0
## Mines of this plot by id: { x, y, width, height, units, refillAt, sprite }.
var _mines := {}
var _mine_seconds := 5.0
var _mine_units := 50
## The mine under the mouse and the one being worked, or -1.
var _hover_mine := -1
var _work_mine := -1
## Objects put on the plot: tile → { id, kind, name }.
var _placed := {}
## The kind being put on the plot from the inventory, or "".
var _placing := ""
## The placed object whose window is open, or (-1, -1).
var _using := Vector2i(-1, -1)
## Which way the next belt or inserter will face (see DIRECTIONS).
var _place_rotation := 1
var _logistics: PlotLogistics
var _next_logistics_poll := 0.0
var _polling_logistics := false

var _astar := AStarGrid2D.new()
var _sources := {}
var _images := {}
var _chunks := {}
var _player_chunk := Vector2i(-99, -99)

var _ground: Node2D
var _field_layer: TileMapLayer
var _field_source := 0
var _shadows: TileMapLayer
var _marks: Node2D
var _sorted: Node2D
var _objects: TileMapLayer
var _station: Sprite2D
var _player: GaragePlayer
var _camera := Camera2D.new()
var _zoom := 1.0
## Fingers on the screen, by index, and their distance at the last step of a pinch.
var _touches := {}
var _pinch := 0.0

var _path: PackedVector2Array = []
var _on_arrival := Callable()
var _hovered := Vector2i(-1, -1)
## Objects in front of the player, drawn see-through so the character never gets lost.
var _faded := {}
var _hover_station := false
## The tile being worked, and seconds of work left.
var _work := Vector2i(-1, -1)
var _work_left := 0.0
## "harvest" for trees, rocks and dunes, "till" for the hoe, "mine" for a mine.
var _work_mode := "harvest"

var _hud: Control
var _title: Label
var _subtitle: Label
var _level: Label
var _xp_bar: ProgressBar
var _money: Label
var _tool_slot: ToolSlot
var _hint: Label
var _prompt: Label
var _field_label: Label
var _crop_menu: PopupMenu
## Turn or pick up a belt or inserter.
var _object_menu: PopupMenu
var _menu_object := Vector2i(-1, -1)
var _menu_cell := Vector2i(-1, -1)
var _work_bar: ProgressBar
var _toast: Label
var _toast_tween: Tween
var _minimap: TextureRect
var _minimap_image: Image
var _minimap_dot: Control
var _loading: Label

var _inventory_window: GameWindow
var _slots: InventoryGrid
var _station_window: GameWindow
var _crafting_window: CraftingWindow
var _furnace_window: FurnaceWindow
var _storage_window: StorageWindow
var _splitter_window: SplitterWindow
var _machine_window: MachineWindow
var _station_box: VBoxContainer
var _station_state := {}
var _clock_offset := 0.0
var _next_station_poll := 0.0
var _trip_labels: Array = []
var _send_to: OptionButton
var _send_x: SpinBox
var _send_y: SpinBox
var _send_item: OptionButton
var _send_quantity: SpinBox
var _send_info: Label
var _send_button: Button


func _ready() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key: Key in ACTIONS[action]:
				var event := InputEventKey.new()
				event.physical_keycode = key
				InputMap.action_add_event(action, event)
	RenderingServer.set_default_clear_color(Color("#08090a"))
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE))
	_build_world()
	_build_hud()
	_build_windows()
	_load()


func _exit_tree() -> void:
	RenderingServer.set_default_clear_color(UI.BACKGROUND)


# --- World ---------------------------------------------------------------------------

func _build_world() -> void:
	_ground = Node2D.new()
	add_child(_ground)
	# Tilled fields lie flat on the ground, under every shadow.
	_field_layer = TileMapLayer.new()
	var field_set := TileSet.new()
	field_set.tile_size = Vector2i(TILE)
	_field_source = _add_source(field_set, "field", "field", false)
	_field_layer.tile_set = field_set
	add_child(_field_layer)
	_shadows = TileMapLayer.new()
	_shadows.tile_set = _tile_set(true)
	add_child(_shadows)
	# Belts lie on the ground under everything standing; inserter arms stand among the rest.
	_logistics = PlotLogistics.new()
	_logistics.tile = TILE
	_logistics.layout = _layout
	_logistics.server_now = _server_now
	add_child(_logistics)
	# Rings on the ground under the object the mouse points at.
	_marks = Node2D.new()
	_marks.draw.connect(_draw_marks)
	add_child(_marks)
	_sorted = Node2D.new()
	_sorted.y_sort_enabled = true
	add_child(_sorted)
	_objects = TileMapLayer.new()
	_objects.y_sort_enabled = true
	_objects.tile_set = _tile_set(false)
	_sorted.add_child(_objects)
	_logistics.arms_parent = _sorted

	_player = GaragePlayer.new(Game.character.get("appearance", {}), Game.appearance_options)
	_player.light = LIGHT
	_player.scale = Vector2.ONE * PLAYER_SCALE
	_player.shadow.scale = Vector2.ONE * PLAYER_SCALE
	_player.visible = false
	_player.shadow.visible = false
	add_child(_player.shadow)
	move_child(_player.shadow, _marks.get_index())
	_sorted.add_child(_player)

	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)


## One atlas source per sprite, so every sprite keeps its own size and anchor; an alternative
## tile of each object is brightened for the mouse.
func _tile_set(shadows: bool) -> TileSet:
	var set := TileSet.new()
	set.tile_size = Vector2i(TILE)
	var sprites: Array[String] = []
	for kind: int in SPRITES:
		sprites.append_array(SPRITES[kind])
	sprites.append_array(["sapling", "tree_young"])
	sprites.append_array(PLACED_SPRITES.values())
	for sprite in sprites:
		_add_source(set, sprite, sprite + ("_shadow" if shadows else ""), not shadows)
	if not shadows:
		# Crops have no shadows of their own; their ids come after those of nature in both sets.
		sprites = ["sprout"]
		for crop: String in CROPS:
			sprites.append_array([crop + "_young", crop + "_ripe"])
		for sprite in sprites:
			_add_source(set, sprite, sprite, true)
	return set


## Adds one sprite as a tile anchored on the cell's centre; with `looks`, also a brightened
## (alternative 1) and a see-through (alternative 2) version. Returns the source id.
func _add_source(set: TileSet, sprite: String, file: String, looks: bool) -> int:
	var texture: Texture2D = load("res://art/plot/%s.png" % file)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(texture.get_size())
	source.create_tile(Vector2i.ZERO)
	var anchor := Vector2i(_layout[sprite]["anchorX"], _layout[sprite]["anchorY"])
	var origin := anchor - Vector2i(texture.get_size() / 2)
	source.get_tile_data(Vector2i.ZERO, 0).texture_origin = origin
	if looks:
		for modulate: Color in [Color(1.45, 1.4, 1.25), Color(1, 1, 1, 0.4)]:
			var alternative := source.create_alternative_tile(Vector2i.ZERO)
			var data := source.get_tile_data(Vector2i.ZERO, alternative)
			data.texture_origin = origin
			data.modulate = modulate
	var id := set.add_source(source)
	if looks:
		_sources[sprite] = id
		_images[sprite] = texture.get_image()
	return id


func _apply_plot(plot: Dictionary) -> void:
	_plot = plot
	_size = plot["size"]
	_harvest_seconds = plot["harvestSeconds"]
	_chop_seconds = plot.get("chopSeconds", _harvest_seconds)
	_mine_seconds = plot.get("mineSeconds", _chop_seconds)
	_mine_units = plot.get("mineUnits", _mine_units)
	var grow: Variant = plot.get("treeGrowSeconds")
	_tree_grow_seconds = float(grow) if grow != null else 0.0
	var packed := Marshalls.base64_to_raw(plot["tiles"])
	_tiles = packed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if plot.get("tool") != null:
		Game.character["tool"] = plot["tool"]
	else:
		Game.character["tool"] = null
	_tool_slot.refresh()
	_fertile = plot.get("fertile", false)
	for crop: Dictionary in plot.get("crops", []):
		_crops[crop["id"]] = crop
	_clock_offset = float(plot["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	for field: Dictionary in plot.get("fields", []):
		_fields[Vector2i(field["tileX"], field["tileY"])] = {"crop": field["crop"], "readyAt": field["readyAt"]}
	for tree: Dictionary in plot.get("trees", []):
		_trees[Vector2i(tree["tileX"], tree["tileY"])] = tree["readyAt"]
	for object: Dictionary in plot.get("objects", []):
		_placed[Vector2i(object["tileX"], object["tileY"])] = object
	_logistics.set_objects(_placed)

	# The ground: the biome's texture repeated over the plot, squashed to the 45° view.
	var floor_name: String = FLOORS.get(int(plot["biome"]), "grass")
	var ground := Sprite2D.new()
	ground.texture = load("res://art/plot/floor_%s.png" % floor_name)
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.centered = false
	ground.region_enabled = true
	var squash := TILE.y / TILE.x
	ground.region_rect = Rect2(0, 0, _size * TILE.x, _size * TILE.y / squash)
	ground.scale = Vector2(1, squash)
	_ground.add_child(ground)
	# A dark band around the edge of the plot.
	var edge := Line2D.new()
	edge.points = PackedVector2Array([Vector2.ZERO, Vector2(_size * TILE.x, 0), _size * TILE, Vector2(0, _size * TILE.y), Vector2.ZERO])
	edge.width = 6
	edge.default_color = Color(0.9, 0.7, 0.3, 0.35)
	_ground.add_child(edge)

	# The railway across the plot.
	var rail := Sprite2D.new()
	rail.texture = load("res://art/plot/rail.png")
	rail.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	rail.region_enabled = true
	rail.centered = false
	var rail_height: float = rail.texture.get_height()
	rail.region_rect = Rect2(0, 0, _size * TILE.x + 512, rail_height)
	rail.position = Vector2(-256, (int(plot["railRow"]) + 0.5) * TILE.y - float(_layout["rail"]["anchorY"]))
	_ground.add_child(rail)

	# The station stands on its tiles with the middle of its south edge as anchor.
	var s: Dictionary = plot["station"]
	var foot := Vector2((int(s["x"]) + int(s["width"]) / 2.0) * TILE.x, (int(s["y"]) + int(s["height"])) * TILE.y)
	var station_anchor := Vector2(_layout["station"]["anchorX"], _layout["station"]["anchorY"])
	_station = Sprite2D.new()
	_station.texture = load("res://art/plot/station.png")
	_station.centered = false
	_station.offset = -station_anchor
	_station.position = foot
	_sorted.add_child(_station)
	_images["station"] = _station.texture.get_image()
	var station_shadow := Sprite2D.new()
	station_shadow.texture = load("res://art/plot/station_shadow.png")
	station_shadow.centered = false
	station_shadow.offset = -station_anchor
	station_shadow.position = foot
	_shadows.add_child(station_shadow)
	for mine: Dictionary in plot.get("mines", []):
		_add_mine(mine)

	_build_paths()
	_build_minimap()
	_camera.limit_left = -200
	_camera.limit_top = -320
	_camera.limit_right = int(_size * TILE.x) + 200
	_camera.limit_bottom = int(_size * TILE.y) + 200

	var spawn := Vector2(plot["spawn"]["x"], plot["spawn"]["y"]) + Vector2(0.5, 0.5)
	_player.visible = true
	_player.shadow.visible = true
	_place_player(spawn)
	_player.face(Vector2(0, -1))
	_camera.position = _player.position
	_camera.reset_smoothing()
	_update_chunks(true)
	_ready_to_play = true


func _tile(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= _size or cell.y >= _size:
		return -1
	return _tiles[cell.y * _size + cell.x]


func _variant(kind: int, cell: Vector2i) -> String:
	var options: Array = SPRITES[kind]
	var h := (cell.x * 73856093) ^ (cell.y * 19349663)
	return options[absi(h) % options.size()]


func _cell_centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


## Draws the chunks near the player and forgets the far ones.
func _update_chunks(force := false) -> void:
	var here := Vector2i((_player.floor_pos / CHUNK).floor())
	if here == _player_chunk and not force:
		return
	_player_chunk = here
	for chunk: Vector2i in _chunks.keys():
		if absi(chunk.x - here.x) > CHUNK_RADIUS + 1 or absi(chunk.y - here.y) > CHUNK_RADIUS + 1:
			_chunks.erase(chunk)
			for y in CHUNK:
				for x in CHUNK:
					var cell := chunk * CHUNK + Vector2i(x, y)
					_objects.erase_cell(cell)
					_shadows.erase_cell(cell)
					_field_layer.erase_cell(cell)
					_stages.erase(cell)
	for cy in range(here.y - CHUNK_RADIUS, here.y + CHUNK_RADIUS + 1):
		for cx in range(here.x - CHUNK_RADIUS, here.x + CHUNK_RADIUS + 1):
			var chunk := Vector2i(cx, cy)
			if _chunks.has(chunk) or cx < 0 or cy < 0 or cx * CHUNK >= _size or cy * CHUNK >= _size:
				continue
			_chunks[chunk] = true
			for y in CHUNK:
				for x in CHUNK:
					_draw_cell(chunk * CHUNK + Vector2i(x, y))


func _draw_cell(cell: Vector2i) -> void:
	if _fields.has(cell):
		_field_layer.set_cell(cell, _field_source, Vector2i.ZERO)
	else:
		_field_layer.erase_cell(cell)
	var sprite := _sprite_at(cell)
	if sprite == "":
		_objects.erase_cell(cell)
		_shadows.erase_cell(cell)
		_stages.erase(cell)
		return
	var id: int = _sources[sprite]
	var look := 1 if cell == _hovered else (2 if _faded.has(cell) else 0)
	_objects.set_cell(cell, id, Vector2i.ZERO, look)
	if _fields.has(cell) or _trees.has(cell):
		_stages[cell] = sprite
	if _fields.has(cell):
		_shadows.erase_cell(cell)
	else:
		_shadows.set_cell(cell, id, Vector2i.ZERO)


## The sprite standing on a tile: nature, the crop growing on a field or a planted tree; "" for nothing.
func _sprite_at(cell: Vector2i) -> String:
	if _placed.has(cell):
		return PLACED_SPRITES.get(_placed[cell]["kind"], "")  # "" for a belt
	if _fields.has(cell):
		return _crop_sprite(cell)
	if _trees.has(cell):
		return _tree_sprite(cell)
	var kind := _tile(cell)
	return _variant(kind, cell) if SPRITES.has(kind) else ""


func _crop_sprite(cell: Vector2i) -> String:
	var field: Dictionary = _fields[cell]
	if field["crop"] == null:
		return ""
	var left := _crop_left(cell)
	if left <= 0.0:
		return field["crop"] + "_ripe"
	var grow: float = _crops.get(field["crop"], {}).get("growSeconds", 60.0)
	return "sprout" if left > grow * SPROUT_UNTIL else field["crop"] + "_young"


func _tree_sprite(cell: Vector2i) -> String:
	var left := _tree_left(cell)
	if left <= 0.0:
		var h := (cell.x * 73856093) ^ (cell.y * 19349663)
		return GROWN_TREES[absi(h) % GROWN_TREES.size()]
	return "sapling" if left > _tree_grow_seconds * SAPLING_UNTIL else "tree_young"


## Seconds until a planted tree can be cut (0 when it can).
func _tree_left(cell: Vector2i) -> float:
	return maxf((float(_trees[cell]) - _server_now()) / 1000.0, 0.0)


func _tree_grown(cell: Vector2i) -> bool:
	return _trees.has(cell) and _tree_left(cell) <= 0.0


## What is worked on a tile: a grown planted tree counts as a tree.
func _work_kind(cell: Vector2i) -> int:
	return TREE if _tree_grown(cell) else _tile(cell)


## Seconds until the crop on a field is ripe (0 when it is).
func _crop_left(cell: Vector2i) -> float:
	var ready_at: Variant = _fields[cell]["readyAt"]
	return maxf((float(ready_at) - _server_now()) / 1000.0, 0.0) if ready_at != null else 0.0


func _ripe(cell: Vector2i) -> bool:
	return _fields.has(cell) and _fields[cell]["crop"] != null and _crop_left(cell) <= 0.0


## Swaps the sprites of crops and trees that grew into their next stage.
func _update_stages() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_stage_check:
		return
	_next_stage_check = now + 1.0
	for cell: Vector2i in _stages.keys():
		if _sprite_at(cell) != _stages[cell]:
			_draw_cell(cell)


# --- Walking ---------------------------------------------------------------------------

func _build_paths() -> void:
	_astar.region = Rect2i(0, 0, _size, _size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in _size:
		for x in _size:
			if _tiles[y * _size + x] in SOLID:
				_astar.set_point_solid(Vector2i(x, y), true)
	for cell: Vector2i in _placed:
		_astar.set_point_solid(cell, not _is_belt(cell))


func _solid(cell: Vector2i) -> bool:
	var kind := _tile(cell)
	return kind < 0 or kind in SOLID or (_placed.has(cell) and not _is_belt(cell))


func _is_belt(cell: Vector2i) -> bool:
	return _placed.has(cell) and _placed[cell]["kind"] == BELT


## Belts, inserters and splitters are turned and picked up from a menu; other placed objects open a window.
func _turnable(cell: Vector2i) -> bool:
	return _placed.has(cell) and _placed[cell]["kind"] in MACHINERY


## Whether the player can stand at a position (in tiles).
func _free(pos: Vector2) -> bool:
	for offset: Vector2 in [Vector2(-RADIUS, 0), Vector2(RADIUS, 0), Vector2(0, -RADIUS * 0.5), Vector2(0, RADIUS * 0.5)]:
		if _solid(Vector2i((pos + offset).floor())):
			return false
	return true


func _place_player(pos: Vector2) -> void:
	_player.floor_pos = pos
	_player.position = pos * TILE
	_player.shadow.position = _player.position


## Walks to a tile along a path around the trees and rocks, then calls `arrival`. When the
## tile itself is blocked (a tree to cut), the path ends next to it.
func _walk_to(cell: Vector2i, arrival := Callable(), stop_next_to := false) -> void:
	var from := Vector2i(_player.floor_pos.floor())
	var target_solid := _astar.is_point_solid(cell) if _astar.region.has_point(cell) else true
	if stop_next_to and _astar.region.has_point(cell):
		_astar.set_point_solid(cell, false)
	var cells := _astar.get_id_path(from, cell.clamp(Vector2i.ZERO, Vector2i(_size - 1, _size - 1)), true)
	if stop_next_to and _astar.region.has_point(cell):
		_astar.set_point_solid(cell, target_solid)
		if not cells.is_empty() and cells[-1] == cell:
			cells.remove_at(cells.size() - 1)
	_path = PackedVector2Array()
	for i in range(1, cells.size()):
		_path.append(Vector2(cells[i]) + Vector2(0.5, 0.5))
	_on_arrival = arrival
	if _path.is_empty():
		_arrive()


func _arrive() -> void:
	var arrival := _on_arrival
	_on_arrival = Callable()
	if arrival.is_valid():
		arrival.call()


func _move_player(delta: float) -> void:
	var step := Vector2.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _focus_in_text():
		input = Vector2.ZERO
	if input != Vector2.ZERO:
		_path = PackedVector2Array()
		_on_arrival = Callable()
		_stop_work()
		step = input * SPEED * delta
	elif not _path.is_empty():
		var to_next := _path[0] - _player.floor_pos
		var length := SPEED * delta
		if to_next.length() <= length:
			step = to_next
			_path.remove_at(0)
		else:
			step = to_next.normalized() * length
	var start := _player.floor_pos
	var pos := start
	# Slide along whatever blocks the way, one axis at a time.
	if _free(pos + Vector2(step.x, 0)):
		pos.x += step.x
	if _free(pos + Vector2(0, step.y)):
		pos.y += step.y
	_player.walking = pos.distance_to(start) > 0.0001
	if _player.walking:
		# The character's "up" is away from the camera, which is -y here.
		_player.face(Vector2(step.x, -step.y))
		_place_player(pos)
	elif not _path.is_empty():
		_path = PackedVector2Array()  # Stuck: give up instead of pushing against a tree.
	if _path.is_empty() and _on_arrival.is_valid():
		_arrive()


func _focus_in_text() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is SpinBox


# --- Mouse -------------------------------------------------------------------------------

## The object drawn under a point of the world: the front-most sprite with a solid pixel there.
func _object_at(point: Vector2) -> Vector2i:
	var cells := _objects_at(point, true)
	return cells[0] if not cells.is_empty() else Vector2i(-1, -1)


## Every object drawn over a point, front-most first.
func _objects_at(point: Vector2, first_only := false) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var base := Vector2i((point / TILE).floor())
	for dy in range(7, -2, -1):
		for dx in [0, -1, 1, -2, 2]:
			var cell := base + Vector2i(dx, dy)
			var sprite := _sprite_at(cell)
			if sprite == "":
				continue
			var image: Image = _images[sprite]
			var pixel := Vector2i(point - _cell_centre(cell)) + Vector2i(_layout[sprite]["anchorX"], _layout[sprite]["anchorY"])
			if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel) and image.get_pixelv(pixel).a > 0.4:
				found.append(cell)
				if first_only:
					return found
	return found


## Makes the objects standing in front of the character see-through.
func _update_fade() -> void:
	var covering := {}
	for lift in [8.0, 30.0, 52.0]:
		for cell in _objects_at(_player.position - Vector2(0, lift)):
			if _cell_centre(cell).y > _player.position.y:
				covering[cell] = true
	if covering == _faded:
		return
	var changed := _faded.keys()
	changed.append_array(covering.keys())
	_faded = covering
	for cell: Vector2i in changed:
		_draw_cell(cell)


func _station_at(point: Vector2) -> bool:
	if _station == null:
		return false
	var pixel := Vector2i(point - _station.position - _station.offset)
	var image: Image = _images["station"]
	return Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel) and image.get_pixelv(pixel).a > 0.4


func _update_hover() -> void:
	var cell := Vector2i(-1, -1)
	var station := false
	var mine := -1
	if _ready_to_play and get_viewport().gui_get_hovered_control() == null:
		var mouse := get_global_mouse_position()
		cell = _object_at(mouse)
		if cell.x < 0 and _is_belt(Vector2i((mouse / TILE).floor())):
			cell = Vector2i((mouse / TILE).floor())
		station = cell == Vector2i(-1, -1) and _station_at(mouse)
		if cell == Vector2i(-1, -1) and not station:
			mine = _mine_at(mouse)
	if cell != _hovered:
		var old := _hovered
		_hovered = cell
		if old.x >= 0:
			_draw_cell(old)
		if cell.x >= 0:
			_draw_cell(cell)
	_hover_station = station
	if station:
		_station.modulate = Color(1.2, 1.17, 1.08)
	elif _station != null:
		_station.modulate = Color.WHITE
	if mine != _hover_mine:
		if _mines.has(_hover_mine):
			_mines[_hover_mine]["sprite"].modulate = Color.WHITE
		_hover_mine = mine
		if mine >= 0:
			_mines[mine]["sprite"].modulate = Color(1.25, 1.2, 1.1)
	var ground := _ground_cell()
	var pointing := cell.x >= 0 or station or mine >= 0 or _fields.has(ground) or _can_till(ground) or _can_plant(ground) or _can_place(ground)
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if pointing else Input.CURSOR_ARROW)
	_marks.queue_redraw()
	_update_prompt()
	if mine >= 0:
		_update_mine_label(mine)
	else:
		_update_field_label(cell if cell.x >= 0 and (_fields.has(cell) or _trees.has(cell) or _placed.has(cell)) else ground)


## The tile under the mouse, or (-1, -1) when the mouse is over the interface.
func _ground_cell() -> Vector2i:
	if not _ready_to_play or get_viewport().gui_get_hovered_control() != null:
		return Vector2i(-1, -1)
	return Vector2i((get_global_mouse_position() / TILE).floor())


## Whether the hoe can turn this tile into a field.
func _can_till(cell: Vector2i) -> bool:
	return _placing == "" and _fertile and Game.tool().get("id", "") == "tool_hoe" and _tile(cell) == NONE and not _fields.has(cell) and not _placed.has(cell)


## Whether a sapling can be planted on this tile now.
func _can_plant(cell: Vector2i) -> bool:
	return _planting and _tree_grow_seconds > 0.0 and _tile(cell) == NONE and not _fields.has(cell) and not _trees.has(cell) and not _placed.has(cell)


## Whether the object being placed can go on this tile: free ground, not under the player.
func _can_place(cell: Vector2i) -> bool:
	var spawn: Dictionary = _plot.get("spawn", {})
	return _placing != "" and _tile(cell) == NONE and not _fields.has(cell) and not _trees.has(cell) and not _placed.has(cell) \
		and cell != Vector2i(spawn.get("x", -1), spawn.get("y", -1)) and Vector2i(_player.floor_pos.floor()) != cell


## The name of the crop or planted tree under the mouse and how long until it is ripe.
func _update_field_label(cell: Vector2i) -> void:
	_field_label.visible = (_fields.has(cell) or _trees.has(cell) or _placed.has(cell)) and _menu_cell.x < 0
	if not _field_label.visible:
		return
	var crop: Variant = _fields[cell]["crop"] if _fields.has(cell) else null
	if _placed.has(cell):
		_field_label.text = _placed_label(cell)
	elif _trees.has(cell):
		if _tree_grown(cell):
			_field_label.text = "Drzewo: urosło, zetnij je siekierą"
		else:
			var left := ceili(_tree_left(cell))
			_field_label.text = "Sadzonka: urośnie za %d:%02d" % [left / 60, left % 60]
	elif crop == null:
		_field_label.text = "Zaorane pole: kliknij, aby zasiać"
	elif _ripe(cell):
		_field_label.text = "%s: dojrzała, kliknij, aby zebrać" % _crops[crop]["name"]
	else:
		var left := ceili(_crop_left(cell))
		_field_label.text = "%s: dojrzeje za %d:%02d" % [_crops[crop]["name"], left / 60, left % 60]
	_field_label.reset_size()
	_field_label.position = _screen(_cell_centre(cell)) - Vector2(_field_label.size.x / 2, 70 * _zoom + 24)


func _placed_label(cell: Vector2i) -> String:
	var object: Dictionary = _placed[cell]
	var facing: String = DIRECTIONS[int(object.get("rotation", 0)) & 3]
	if object["kind"] == BELT:
		return "Taśmociąg %s: [R] obróć, kliknij, aby schować" % facing
	if object["kind"] == INSERTER:
		var held := _logistics.held(cell)
		var carrying := ", niesie: %s" % _item_name(held).to_lower() if held != "" else ""
		return "Podajnik %s%s: [R] obróć, kliknij, aby schować" % [facing, carrying]
	if object["kind"] == SPLITTER:
		var filter := _logistics.splitter(object["id"])
		var sorting := "na zmianę w lewo i w prawo" if (filter["items"] as Array).is_empty() \
			else "wybrane %s" % ("w lewo" if int(filter["side"]) == 0 else "w prawo")
		return "Rozdzielacz %s, %s: [R] obróć, kliknij po więcej" % [facing, sorting]
	var summary := _logistics.storage(object["id"])
	if not summary.is_empty():
		var fill := "%d/%d miejsc" % [int(summary["usedSlots"]), int(summary["slots"])] if int(summary["slots"]) > 1 \
			else "%d/%d" % [int(summary["stored"]), int(summary["capacity"])]
		return "%s (%s): kliknij, aby otworzyć" % [object["name"], fill]
	return "%s: kliknij, aby użyć" % object["name"]


func _draw_marks() -> void:
	if _hovered.x >= 0 and WORK.has(_work_kind(_hovered)) and not _fields.has(_hovered):
		var ok: bool = Game.tool().get("id", "") == WORK[_work_kind(_hovered)]["tool"]
		_draw_ring(_cell_centre(_hovered), Color(0.96, 0.69, 0.25, 0.8) if ok else Color(1.0, 0.42, 0.35, 0.8))
	var ground := _ground_cell()
	if _hovered.x >= 0 and _placed.has(_hovered):
		_draw_ring(_cell_centre(_hovered), Color(0.96, 0.69, 0.25, 0.8))
	if _placing != "" and ground.x >= 0:
		_draw_ring(_cell_centre(ground), Color(0.56, 0.84, 0.35, 0.8) if _can_place(ground) else Color(1.0, 0.42, 0.35, 0.8))
		_draw_ghost(ground)
	elif _hovered.x < 0 and (_fields.has(ground) or _can_till(ground) or _can_plant(ground)):
		_draw_ring(_cell_centre(ground), Color(0.56, 0.84, 0.35, 0.8))
	if _work.x >= 0:
		_draw_ring(_cell_centre(_work), Color(1, 1, 1, 0.7))


## What is being placed, see-through on the tile under the mouse, with the way it will face.
func _draw_ghost(cell: Vector2i) -> void:
	var sprite: String = PlotLogistics.BELT_SPRITES[_place_rotation] if _placing == BELT else PLACED_SPRITES.get(_placing, "")
	if sprite == "" or not _layout.has(sprite):
		return
	var texture: Texture2D = load("res://art/plot/%s.png" % sprite)
	var anchor := Vector2(_layout[sprite]["anchorX"], _layout[sprite]["anchorY"])
	_marks.draw_texture(texture, _cell_centre(cell) - anchor, Color(1, 1, 1, 0.55))
	if _placing in MACHINERY:
		var dir := Vector2(PlotLogistics.facing(_place_rotation)) * TILE
		var from := _cell_centre(cell) - dir * 0.35 - Vector2(0, 10)
		var to := _cell_centre(cell) + dir * 0.45 - Vector2(0, 10)
		var head := (to - from).normalized()
		var side := Vector2(-head.y, head.x)
		var color := Color(0.56, 0.84, 0.35, 0.95)
		_marks.draw_line(from, to, color, 3.0, true)
		_marks.draw_colored_polygon([to + head * 4, to - head * 9 + side * 7, to - head * 9 - side * 7], color)


func _draw_ring(at: Vector2, color: Color) -> void:
	_marks.draw_set_transform(at, 0, Vector2(1, TILE.y / TILE.x))
	_marks.draw_arc(Vector2.ZERO, TILE.x * 0.55, 0, TAU, 40, color, 2.5, true)
	_marks.draw_set_transform(Vector2.ZERO)


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_play or _pinch_zoom(event):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom * 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom / 1.1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_update_hover()
			var cell := Vector2i((get_global_mouse_position() / TILE).floor())
			if _placing != "":
				if _can_place(cell):
					_go_and(cell, _place_object, true)
				else:
					_show_toast("Tu nie można tego postawić. Wybierz wolne pole.", UI.ERROR)
			elif _hovered.x >= 0:
				_act_on(_hovered)
			elif _hover_station:
				_go_to_station()
			elif _hover_mine >= 0:
				_go_to_mine(_hover_mine)
			elif _fields.has(cell):
				_act_on(cell)
			elif _can_plant(cell):
				_go_and(cell, _plant_tree)
			elif _can_till(cell):
				_till(cell)
			else:
				_stop_work()
				if _tile(cell) >= 0:
					_walk_to(cell)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel"):
		if _placing != "":
			_stop_placing()
		elif _station_window.visible or _inventory_window.visible or _using_window_open():
			for window: GameWindow in [_station_window, _inventory_window, _crafting_window, _furnace_window, _machine_window, _storage_window, _splitter_window]:
				window.hide_window()
		elif _planting:
			_set_planting(false)
		else:
			_stop_work()
			_path = PackedVector2Array()
	elif event.is_action_pressed("rotate"):
		if _placing != "":
			_place_rotation = (_place_rotation + 1) % 4
			_update_hint()
		elif _turnable(_hovered):
			_rotate_placed(_hovered)
	elif event.is_action_pressed("interact"):
		if _nearest_placed().x >= 0:
			var at := _nearest_placed()
			if _using == at and _using_window_open():
				_hide_placed_windows()
			else:
				_use_placed(at)
		elif _near_station():
			_station_window.toggle()
			if _station_window.visible:
				_refresh_station()
		elif _nearest_mine() >= 0 and _nearest_work().x < 0:
			_go_to_mine(_nearest_mine())
		else:
			var cell := _nearest_work()
			if cell.x >= 0:
				_act_on(cell)
	elif event.is_action_pressed("inventory"):
		_inventory_window.toggle()
		if _inventory_window.visible:
			_reload_inventory()
	elif event.is_action_pressed("station"):
		_go_to_station()
	elif event.is_action_pressed("tool"):
		_tool_slot.open()
	elif event.is_action_pressed("plant"):
		_set_planting(not _planting)
	elif event.is_action_pressed("world_map"):
		Game.open_world_map()
	elif event.is_action_pressed("garage"):
		Game.open_garage()


## Zooms with two fingers on a touch screen or a pinch on a touchpad; true if it did.
func _pinch_zoom(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:
		_set_zoom(_zoom * event.factor)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch = 0.0
		return false
	elif event is InputEventScreenDrag and _touches.size() == 2:
		_touches[event.index] = event.position
		var distance: float = _touches.values()[0].distance_to(_touches.values()[1])
		if _pinch > 0.0:
			_set_zoom(_zoom * distance / _pinch)
		_pinch = distance
	else:
		return false
	get_viewport().set_input_as_handled()
	return true


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	_camera.zoom = Vector2.ONE * _zoom


# --- Working trees, rocks and dunes ----------------------------------------------------------

func _near(cell: Vector2i, distance := REACH) -> bool:
	return _player.floor_pos.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) <= distance


func _nearest_work() -> Vector2i:
	var best := Vector2i(-1, -1)
	var here := Vector2i(_player.floor_pos.floor())
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cell := here + Vector2i(dx, dy)
			if (WORK.has(_work_kind(cell)) or _ripe(cell)) and _near(cell) and (best.x < 0 or _player.floor_pos.distance_to(Vector2(cell)) < _player.floor_pos.distance_to(Vector2(best))):
				best = cell
	return best


## Walks up to a tree, rock or dune and works it with the tool in hand.
func _work_on(cell: Vector2i) -> void:
	var kind := _work_kind(cell)
	if _trees.has(cell) and not _tree_grown(cell):
		var left := ceili(_tree_left(cell))
		_show_toast("Sadzonka urośnie za %d:%02d." % [left / 60, left % 60], UI.MUTED)
		return
	if not WORK.has(kind):
		_show_toast("%s: nie da się tego zebrać." % OBJECT_NAMES.get(kind, "To"), UI.MUTED)
		return
	var work: Dictionary = WORK[kind]
	if Game.tool().get("id", "") != work["tool"]:
		_show_toast("%s: potrzebujesz %s. Zmień narzędzie w slocie [Q]." % [work["name"], work["need"]], UI.ERROR)
		return
	_stop_work()
	if _near(cell):
		_start_work(cell)
		return
	_walk_to(cell, func() -> void:
		if _near(cell) and _work_kind(cell) == kind:
			_start_work(cell)
		elif _work_kind(cell) == kind:
			_show_toast("Nie da się tam podejść.", UI.ERROR), true)


func _start_work(cell: Vector2i, mode := "harvest") -> void:
	_work = cell
	_work_mode = mode
	# Cutting a tree down takes longer than a swing at a rock or a dune.
	_work_seconds = _chop_seconds if mode == "harvest" and _work_kind(cell) == TREE else _harvest_seconds
	if mode == "mine":
		_work_seconds = _mine_seconds
	_work_left = _work_seconds
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	_work_bar.max_value = _work_seconds
	_work_bar.visible = true


func _stop_work() -> void:
	_work = Vector2i(-1, -1)
	_work_mine = -1
	_work_bar.visible = false
	_player.rotation = 0.0


func _update_work(delta: float) -> void:
	if _work.x < 0:
		return
	_work_left -= delta
	_work_bar.value = _work_seconds - _work_left
	_work_bar.position = _screen(_cell_centre(_work)) - Vector2(_work_bar.size.x / 2, 90 * _zoom + 12)
	# Swing: the body leans into each stroke.
	_player.rotation = sin((_work_seconds - _work_left) * TAU * 2.0) * 0.08
	if _work_left <= 0.0:
		var cell := _work
		var mine := _work_mine
		_stop_work()
		if _work_mode == "till":
			_till_request(cell)
		elif _work_mode == "mine":
			_mine_request(mine)
		else:
			_harvest(cell)


func _harvest(cell: Vector2i) -> void:
	var kind := _tile(cell)
	var reply := await Net.request("plot.harvest", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y})
	if reply["type"] != "plot.harvested":
		_show_error(reply)
		if reply["payload"].get("code", "") == "nothing_here":
			_clear_tile(cell, kind)
		return
	var result: Dictionary = reply["payload"]
	_clear_tile(cell, kind)
	var items: Array = result["items"]
	for i in items.size():
		var item: Dictionary = items[i]
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, _cell_centre(cell), i * 0.25, item["id"])
		if item["id"] == "sapling":
			_set_saplings(_saplings + int(item["quantity"]))
	var gained := int(result["xp"]["xp"]) - int(Game.character.get("xp", 0))
	if gained > 0:
		_float_text("+%d XP" % gained, UI.GOLD, _cell_centre(cell), items.size() * 0.25)
	Game.gain_xp(result["xp"])
	_refresh_character()
	if result["xp"].get("leveledUp", false):
		_show_toast("Awans! Poziom %d" % int(result["xp"]["level"]), UI.GOLD)
	if _inventory_window.visible or _station_window.visible:
		_reload_inventory()


## Removes a worked object: it falls over (a tree) or crumbles, and the tile becomes free.
func _clear_tile(cell: Vector2i, kind: int) -> void:
	if _trees.has(cell):
		var sprite := _sprite_at(cell)
		_trees.erase(cell)
		if _hovered == cell:
			_hovered = Vector2i(-1, -1)
		_draw_cell(cell)
		_set_minimap(cell, NONE)
		_vanish(sprite, cell, true)
		return
	if not SPRITES.has(kind):
		return
	var sprite_name := _variant(kind, cell)
	_tiles[cell.y * _size + cell.x] = NONE
	_astar.set_point_solid(cell, false)
	if _hovered == cell:
		_hovered = Vector2i(-1, -1)
	_draw_cell(cell)
	_set_minimap(cell, NONE)
	_vanish(sprite_name, cell, kind == TREE)


## A copy of a sprite that falls over (a tree) or sinks into the ground, then disappears.
func _vanish(sprite_name: String, cell: Vector2i, fall: bool) -> void:
	var falling := Sprite2D.new()
	falling.texture = load("res://art/plot/%s.png" % sprite_name)
	falling.centered = false
	falling.offset = -Vector2(_layout[sprite_name]["anchorX"], _layout[sprite_name]["anchorY"])
	falling.position = _cell_centre(cell)
	_sorted.add_child(falling)
	var tween := create_tween()
	if fall:
		var side := 1.0 if _player.floor_pos.x < cell.x + 0.5 else -1.0
		tween.tween_property(falling, "rotation", side * PI / 2.2, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(falling, "modulate:a", 0.0, 0.4)
	else:
		tween.tween_property(falling, "scale", Vector2(1.15, 0.2), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(falling, "modulate:a", 0.0, 0.35)
	tween.tween_callback(falling.queue_free)


# --- Farming ------------------------------------------------------------------------------------

## What a click on a tile does: work nature, sow an empty field, reap a ripe crop.
func _act_on(cell: Vector2i) -> void:
	if _turnable(cell):
		_open_object_menu(cell)
		return
	if _placed.has(cell):
		_go_and(cell, _use_placed)
		return
	if not _fields.has(cell):
		_work_on(cell)
		return
	var crop: Variant = _fields[cell]["crop"]
	if crop == null:
		_open_crop_menu(cell)
	elif _ripe(cell):
		_go_and(cell, _reap)
	else:
		var left := ceili(_crop_left(cell))
		_show_toast("%s dojrzeje za %d:%02d." % [_crops[crop]["name"], left / 60, left % 60], UI.MUTED)


## Walks onto or next to a tile (always next to it with `next_to`), then calls `action` with it.
func _go_and(cell: Vector2i, action: Callable, next_to := false) -> void:
	_stop_work()
	if _near(cell) and not (next_to and Vector2i(_player.floor_pos.floor()) == cell):
		action.call(cell)
		return
	_walk_to(cell, func() -> void:
		if _near(cell):
			action.call(cell), _solid(cell) or next_to)


func _till(cell: Vector2i) -> void:
	_go_and(cell, func(at: Vector2i) -> void:
		if _can_till(at):
			_start_work(at, "till"))


func _till_request(cell: Vector2i) -> void:
	var reply := await Net.request("plot.till", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y})
	_apply_field(reply)


func _open_crop_menu(cell: Vector2i) -> void:
	_menu_cell = cell
	_crop_menu.clear()
	for i in CROPS.size():
		var crop: Dictionary = _crops.get(CROPS[i], {})
		if crop.is_empty():
			continue
		var minutes := roundi(float(crop["growSeconds"]) / 60.0)
		_crop_menu.add_icon_item(UI.texture("icons/item_" + CROPS[i]),
			"%s  ·  %d min  ·  %d szt." % [crop["name"], minutes, int(crop["yield"])], i)
	_crop_menu.reset_size()
	var at := get_viewport().get_mouse_position() + Vector2(12, 4)
	_crop_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_crop_chosen(index: int) -> void:
	var cell := _menu_cell
	_menu_cell = Vector2i(-1, -1)
	var crop: String = CROPS[index]
	_go_and(cell, func(at: Vector2i) -> void: _plant(at, crop))


func _plant(cell: Vector2i, crop: String) -> void:
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var reply := await Net.request("plot.plant", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y, "crop": crop})
	_apply_field(reply)


func _reap(cell: Vector2i) -> void:
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var sprite := _sprite_at(cell)
	var reply := await Net.request("plot.reap", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y})
	if reply["type"] == "plot.field" and sprite != "":
		_vanish(sprite, cell, false)
	_apply_field(reply)


## Shows the server's answer to tilling, sowing or reaping.
func _apply_field(reply: Dictionary) -> void:
	if reply["type"] != "plot.field":
		_show_error(reply)
		return
	var result: Dictionary = reply["payload"]
	_clock_offset = float(result["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	var field: Dictionary = result["field"]
	var cell := Vector2i(field["tileX"], field["tileY"])
	_fields[cell] = {"crop": field["crop"], "readyAt": field["readyAt"]}
	_draw_cell(cell)
	_set_minimap(cell, NONE)
	var items: Array = result["items"]
	for i in items.size():
		var item: Dictionary = items[i]
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, _cell_centre(cell), i * 0.25, item["id"])
	if result.get("xp") != null:
		var gained := int(result["xp"]["xp"]) - int(Game.character.get("xp", 0))
		if gained > 0:
			_float_text("+%d XP" % gained, UI.GOLD, _cell_centre(cell), items.size() * 0.25)
		Game.gain_xp(result["xp"])
		_refresh_character()
	if not items.is_empty() and (_inventory_window.visible or _station_window.visible):
		_reload_inventory()


# --- Forestry -----------------------------------------------------------------------------------

## Turns planting on or off: while on, a click on free ground plants a sapling from the inventory.
func _set_planting(on: bool) -> void:
	if on and _tree_grow_seconds <= 0.0:
		_show_toast("Na lodowcu nic nie wyrośnie.", UI.ERROR)
		on = false
	elif on and _saplings <= 0:
		_show_toast("Nie masz sadzonek. Kupisz je na rynku w garażu (od handlarza albo od innych graczy).", UI.ERROR)
		on = false
	_planting = on
	if on:
		_stop_work()
		var minutes := _tree_grow_seconds / 60.0
		_show_toast("Sadzenie: kliknij wolne pole. Drzewo urośnie tu w %s min." % str(snappedf(minutes, 0.1)).trim_suffix(".0").replace(".", ","))
	_update_plant_button()
	_update_hint()


func _set_saplings(count: int) -> void:
	_saplings = maxi(count, 0)
	if _saplings == 0:
		_planting = false
	_update_plant_button()
	_update_hint()


func _update_plant_button() -> void:
	if _plant_button == null:
		return
	_plant_button.text = ("Koniec sadzenia  [P]" if _planting else "Sadź drzewa  [P]") + "  · %d" % _saplings
	_plant_button.modulate = Color(0.75, 1.0, 0.6) if _planting else Color.WHITE


## Saplings in the inventory, counted from an "inventory" reply.
func _count_saplings(items: Array) -> void:
	var count := 0
	for item: Dictionary in items:
		if item["id"] == "sapling":
			count += int(item["quantity"])
	_set_saplings(count)


func _plant_tree(cell: Vector2i) -> void:
	if not _can_plant(cell):
		return
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var reply := await Net.request("plot.plantTree", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y})
	if reply["type"] != "plot.tree":
		_show_error(reply)
		return
	var result: Dictionary = reply["payload"]
	_clock_offset = float(result["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	var tree: Dictionary = result["tree"]
	var at := Vector2i(tree["tileX"], tree["tileY"])
	_trees[at] = tree["readyAt"]
	_draw_cell(at)
	_set_minimap(at, NONE)
	_float_text("−1 Sadzonka drzewa", UI.MUTED, _cell_centre(at), 0.0, "sapling")
	var gained := int(result["xp"]["xp"]) - int(Game.character.get("xp", 0))
	if gained > 0:
		_float_text("+%d XP" % gained, UI.GOLD, _cell_centre(at), 0.25)
	Game.gain_xp(result["xp"])
	_refresh_character()
	_set_saplings(_saplings - 1)
	if _saplings == 0:
		_show_toast("To była ostatnia sadzonka.", UI.MUTED)
	if _inventory_window.visible or _station_window.visible:
		_reload_inventory()


# --- Workbench and furnace -------------------------------------------------------------------------

## Starts putting a workbench or furnace from the inventory on the plot: a click on free ground places it.
func _start_placing(kind: String) -> void:
	_set_planting(false)
	_stop_work()
	_inventory_window.hide_window()
	_placing = kind
	if kind in MACHINERY:
		_show_toast("Kliknij wolne pole, aby postawić: %s. [R] obraca, Esc kończy." % _item_name(kind).to_lower())
	else:
		_show_toast("Kliknij wolne pole, aby postawić: %s. Esc anuluje." % _item_name(kind))
	_update_hint()


func _stop_placing() -> void:
	_placing = ""
	_update_hint()


func _item_name(item: String) -> String:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return stack["name"]
	return item


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _place_object(cell: Vector2i) -> void:
	if not _can_place(cell):
		_show_toast("Tu nie można tego postawić.", UI.ERROR)
		return
	var kind := _placing
	# Belts and inserters are laid one after another until they run out.
	var more := kind in MACHINERY and _count(kind) > 1
	if not more:
		_stop_placing()
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var reply := await Net.request("plot.place", {"x": _at.x, "y": _at.y, "kind": kind, "tileX": cell.x, "tileY": cell.y, "rotation": _place_rotation})
	if reply["type"] != "plot.placed":
		_show_error(reply)
		return
	var object: Dictionary = reply["payload"]["object"]
	var at := Vector2i(object["tileX"], object["tileY"])
	_placed[at] = object
	_astar.set_point_solid(at, not _is_belt(at))
	_draw_cell(at)
	_logistics.set_objects(_placed)
	if kind in MACHINERY:
		_show_toast("%s stoi %s. %s" % [object["name"], DIRECTIONS[int(object["rotation"])], "Kliknij kolejne pole albo Esc." if more else ""])
	else:
		_show_toast("%s stoi na działce. Kliknij, aby użyć." % object["name"])
	_reload_inventory()
	_poll_logistics()


## The placed object next to the player, or (-1, -1).
func _nearest_placed() -> Vector2i:
	for cell: Vector2i in _placed:
		if _near(cell) and not _turnable(cell):
			return cell
	return Vector2i(-1, -1)


func _use_placed(cell: Vector2i) -> void:
	if not _placed.has(cell):
		return
	var object: Dictionary = _placed[cell]
	_using = cell
	_station_window.hide_window()
	_hide_placed_windows()
	if object["kind"] == "furniture_furnace":
		_furnace_window.open_at(object["id"])
	elif object["kind"] in MACHINES:
		_machine_window.open_at(object["id"], object["name"])
	elif object["kind"] in STORAGES:
		_storage_window.open_at(_at, object["id"])
	elif object["kind"] == "furniture_workbench":
		_crafting_window.open_at(object["id"])


func _using_window_open() -> bool:
	return _crafting_window.visible or _furnace_window.visible or _machine_window.visible or _storage_window.visible \
		or _splitter_window.visible


func _hide_placed_windows() -> void:
	_crafting_window.hide_window()
	_furnace_window.hide_window()
	_machine_window.hide_window()
	_storage_window.hide_window()
	_splitter_window.hide_window()


func _pick_up_placed(id: String) -> void:
	var reply := await Net.request("plot.pickup", {"x": _at.x, "y": _at.y, "id": id})
	if reply["type"] != "plot.pickedUp":
		_show_error(reply)
		return
	for cell: Vector2i in _placed.keys():
		if _placed[cell]["id"] == id:
			_show_toast("%s: schowano do ekwipunku." % _placed[cell]["name"])
			_placed.erase(cell)
			_astar.set_point_solid(cell, _tile(cell) in SOLID)
			if _hovered == cell:
				_hovered = Vector2i(-1, -1)
			_draw_cell(cell)
	_logistics.set_objects(_placed)
	_hide_placed_windows()
	_using = Vector2i(-1, -1)
	_reload_inventory()
	_poll_logistics()


func _open_object_menu(cell: Vector2i) -> void:
	_menu_object = cell
	_object_menu.clear()
	_object_menu.add_item("Obróć  [R]", 0)
	_object_menu.add_item("Schowaj do ekwipunku", 1)
	if _placed.has(cell) and _placed[cell]["kind"] == SPLITTER:
		_object_menu.add_item("Ustaw, co idzie w którą stronę", 2)
	_object_menu.reset_size()
	var at := get_viewport().get_mouse_position() + Vector2(12, 4)
	_object_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_object_chosen(choice: int) -> void:
	var cell := _menu_object
	_menu_object = Vector2i(-1, -1)
	if not _placed.has(cell):
		return
	if choice == 0:
		_rotate_placed(cell)
	elif choice == 2:
		_open_splitter(cell)
	else:
		_go_and(cell, func(at: Vector2i) -> void:
			if _placed.has(at):
				_pick_up_placed(_placed[at]["id"]))


func _open_splitter(cell: Vector2i) -> void:
	var object: Dictionary = _placed[cell]
	_hide_placed_windows()
	_splitter_window.names = _logistics.names
	_splitter_window.set_items(_items)
	_splitter_window.open_at(_at, object["id"], int(object.get("rotation", 0)), _logistics.splitter(object["id"]))


## Turns a belt or inserter a quarter turn anticlockwise: south, east, north, west.
func _rotate_placed(cell: Vector2i) -> void:
	var object: Dictionary = _placed[cell]
	var reply := await Net.request("plot.rotate", {"x": _at.x, "y": _at.y, "id": object["id"], "rotation": (int(object.get("rotation", 0)) + 1) % 4})
	if reply["type"] != "plot.rotated":
		_show_error(reply)
		return
	_placed[cell] = reply["payload"]["object"]
	_logistics.set_objects(_placed)
	_draw_cell(cell)
	_poll_logistics()


## Asks for the belts, inserters and storage as the server has them now.
func _poll_logistics() -> void:
	if _polling_logistics:
		return
	_polling_logistics = true
	_next_logistics_poll = Time.get_ticks_msec() + LOGISTICS_POLL
	var reply := await Net.request("logistics.get", {"x": _at.x, "y": _at.y})
	_polling_logistics = false
	if reply["type"] == "logistics":
		_logistics.apply(reply["payload"])


## Orders from a workbench are done: they are in the inventory now.
func _on_crafted(done: Array, xp: Variant) -> void:
	var at := _cell_centre(_using) if _using.x >= 0 else _player.position
	for i in done.size():
		var item: Dictionary = done[i]
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, at, i * 0.25, item["id"])
	_gain(xp, at, done.size() * 0.25)
	_show_toast("Gotowe: %s. Leży w ekwipunku." % ", ".join(done.map(func(item: Dictionary) -> String: return item["name"])))
	_reload_inventory()


func _on_furnace_changed(taken: Array, xp: Variant) -> void:
	var at := _cell_centre(_using) if _using.x >= 0 else _player.position
	for i in taken.size():
		var item: Dictionary = taken[i]
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, at, i * 0.25, item["id"])
	_gain(xp, at, taken.size() * 0.25)
	_reload_inventory()


func _gain(xp: Variant, at: Vector2, delay: float) -> void:
	if xp == null:
		return
	var gained := int(xp["xp"]) - int(Game.character.get("xp", 0))
	if gained > 0:
		_float_text("+%d XP" % gained, UI.GOLD, at, delay)
	Game.gain_xp(xp)
	_refresh_character()
	if xp.get("leveledUp", false):
		_show_toast("Awans! Poziom %d" % int(xp["level"]), UI.GOLD)


# --- Mining --------------------------------------------------------------------------------------

## Puts a mine on its tiles, with the middle of its south edge as anchor like the station.
func _add_mine(mine: Dictionary) -> void:
	var foot := Vector2((int(mine["x"]) + int(mine["width"]) / 2.0) * TILE.x, (int(mine["y"]) + int(mine["height"])) * TILE.y)
	var anchor := Vector2(_layout["mine"]["anchorX"], _layout["mine"]["anchorY"])
	var sprite := Sprite2D.new()
	sprite.texture = load("res://art/plot/mine.png")
	sprite.centered = false
	sprite.offset = -anchor
	sprite.position = foot
	_sorted.add_child(sprite)
	var shadow := Sprite2D.new()
	shadow.texture = load("res://art/plot/mine_shadow.png")
	shadow.centered = false
	shadow.offset = -anchor
	shadow.position = foot
	_shadows.add_child(shadow)
	if not _images.has("mine"):
		_images["mine"] = sprite.texture.get_image()
	var state := mine.duplicate()
	state["sprite"] = sprite
	_mines[int(mine["id"])] = state


## The mine drawn under a point of the world, or -1.
func _mine_at(point: Vector2) -> int:
	for id: int in _mines:
		var sprite: Sprite2D = _mines[id]["sprite"]
		var pixel := Vector2i(point - sprite.position - sprite.offset)
		var image: Image = _images["mine"]
		if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel) and image.get_pixelv(pixel).a > 0.4:
			return id
	return -1


func _mine_rect(id: int) -> Rect2:
	var mine: Dictionary = _mines[id]
	return Rect2(mine["x"], mine["y"], mine["width"], mine["height"])


func _near_mine(id: int) -> bool:
	var r := _mine_rect(id)
	var p := _player.floor_pos
	return p.distance_to(p.clamp(r.position, r.end)) <= STATION_REACH


## The mine the player stands at, or -1.
func _nearest_mine() -> int:
	for id: int in _mines:
		if _near_mine(id):
			return id
	return -1


## Loads a mine has left now; a worked-out mine is full again once its rest is over.
func _mine_left_units(id: int) -> int:
	var mine: Dictionary = _mines[id]
	if mine["refillAt"] != null and _server_now() >= float(mine["refillAt"]):
		mine["units"] = _mine_units
		mine["refillAt"] = null
	return int(mine["units"])


## Seconds until a worked-out mine is full again.
func _mine_refill_left(id: int) -> int:
	var refill: Variant = _mines[id]["refillAt"]
	return ceili(maxf((float(refill) - _server_now()) / 1000.0, 0.0)) if refill != null else 0


func _update_mine_label(id: int) -> void:
	_field_label.visible = _menu_cell.x < 0
	if _mine_left_units(id) > 0:
		_field_label.text = "Kopalnia: %d/%d jednostek, kliknij, aby wydobywać kilofem" % [_mine_left_units(id), _mine_units]
	else:
		var left := _mine_refill_left(id)
		_field_label.text = "Kopalnia wyczerpana: odnowi się za %d:%02d" % [left / 60, left % 60]
	_field_label.reset_size()
	# Over the entrance, kept on screen when the mine stands at its top edge.
	var foot: Vector2 = _mines[id]["sprite"].position
	_field_label.position = _screen(foot) - Vector2(_field_label.size.x / 2, 150 * _zoom)
	_field_label.position.y = maxf(_field_label.position.y, 130.0)


## Walks to the entrance of a mine and starts mining with the pickaxe.
func _go_to_mine(id: int) -> void:
	if Game.tool().get("id", "") != "tool_pickaxe":
		_show_toast("Kopalnia: potrzebujesz kilofa. Zmień narzędzie w slocie [Q].", UI.ERROR)
		return
	if _mine_left_units(id) <= 0:
		var left := _mine_refill_left(id)
		_show_toast("Kopalnia wyczerpana, odnowi się za %d:%02d." % [left / 60, left % 60], UI.MUTED)
		return
	_stop_work()
	if _near_mine(id):
		_start_mining(id)
		return
	var r := _mine_rect(id)
	var entrance := Vector2i(int(r.get_center().x), int(r.end.y))
	_walk_to(entrance, func() -> void:
		if _near_mine(id):
			_start_mining(id)
		else:
			_show_toast("Nie da się tam podejść.", UI.ERROR))


func _start_mining(id: int) -> void:
	var r := _mine_rect(id)
	_start_work(Vector2i(int(r.get_center().x), int(r.end.y) - 1), "mine")
	_work_mine = id


## One load of ore; the player keeps mining while standing at the mine until it runs dry.
func _mine_request(id: int) -> void:
	var reply := await Net.request("plot.mine", {"x": _at.x, "y": _at.y, "mine": id})
	if reply["type"] != "plot.mined":
		_show_error(reply)
		return
	var result: Dictionary = reply["payload"]
	_clock_offset = float(result["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	var state: Dictionary = result["mine"]
	_mines[id]["units"] = state["units"]
	_mines[id]["refillAt"] = state["refillAt"]
	var r := _mine_rect(id)
	var at := Vector2(r.get_center().x, r.end.y - 1.0) * TILE
	var items: Array = result["items"]
	if items.is_empty():
		_float_text("Pusto, tym razem nic", UI.MUTED, at)
	for i in items.size():
		var item: Dictionary = items[i]
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, at, i * 0.25, item["id"])
	var gained := int(result["xp"]["xp"]) - int(Game.character.get("xp", 0))
	if gained > 0:
		_float_text("+%d XP" % gained, UI.GOLD, at, maxi(items.size(), 1) * 0.25)
	Game.gain_xp(result["xp"])
	_refresh_character()
	if result["xp"].get("leveledUp", false):
		_show_toast("Awans! Poziom %d" % int(result["xp"]["level"]), UI.GOLD)
	if _inventory_window.visible or _station_window.visible:
		_reload_inventory()
	if int(state["units"]) <= 0:
		_show_toast("Kopalnia wyczerpana. Odnowi się za %d min." % roundi(_mine_refill_left(id) / 60.0), UI.MUTED)
	elif _work.x < 0 and _path.is_empty() and _near_mine(id) and Game.tool().get("id", "") == "tool_pickaxe":
		_start_mining(id)


# --- Station -------------------------------------------------------------------------------------

func _station_rect() -> Rect2:
	var s: Dictionary = _plot["station"]
	return Rect2(s["x"], s["y"], s["width"], s["height"])


func _near_station() -> bool:
	if _plot.is_empty():
		return false
	var r := _station_rect()
	var p := _player.floor_pos
	return p.distance_to(p.clamp(r.position, r.end)) <= STATION_REACH


func _go_to_station() -> void:
	if _plot.is_empty():
		return
	var open := func() -> void:
		_station_window.show_window()
		_refresh_station()
	if _near_station():
		open.call()
		return
	var r := _station_rect()
	var door := Vector2i(int(r.get_center().x), int(r.end.y) + 1)
	_walk_to(door, func() -> void:
		if _near_station():
			open.call())


# --- Every frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _ready_to_play:
		return
	_move_player(delta)
	_update_chunks()
	_update_fade()
	_camera.position = _player.position
	_update_hover()
	_update_work(delta)
	_update_minimap_dot()
	_update_stages()
	if _station_window.visible and not _near_station():
		_station_window.hide_window()
	if _using.x >= 0 and (not _placed.has(_using) or not _near(_using, REACH + 1.5)):
		_hide_placed_windows()
		_using = Vector2i(-1, -1)
	if _logistics.has_machinery() and Time.get_ticks_msec() >= _next_logistics_poll:
		_poll_logistics()
	_update_trips()


func _screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


func _update_prompt() -> void:
	var text := ""
	var placed := _nearest_placed()
	if _work.x < 0 and placed.x >= 0:
		if not (_using == placed and _using_window_open()):
			text = "[E] %s" % _placed[placed]["name"]
	elif _work.x < 0 and _near_station() and not _station_window.visible:
		text = "[E] Stacja kolejowa"
	elif _work.x < 0:
		var cell := _nearest_work()
		var mine := _nearest_mine()
		if cell.x < 0 and mine >= 0:
			text = "[E] Wydobywaj: kopalnia (%d/%d)" % [_mine_left_units(mine), _mine_units]
		elif cell.x >= 0:
			if _fields.has(cell):
				text = "[E] Zbierz: %s" % _crops[_fields[cell]["crop"]]["name"].to_lower()
			else:
				var work: Dictionary = WORK[_work_kind(cell)]
				text = "[E] %s: %s" % [work["verb"], work["name"].to_lower()]
	_prompt.visible = text != ""
	if _prompt.visible:
		_prompt.text = text
		_prompt.reset_size()
		_prompt.position = _screen(_player.position) - Vector2(_prompt.size.x / 2, 100 * _zoom + 30)


# --- HUD ---------------------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	# The theme of the root window does not reach through the canvas layer.
	_hud.theme = UI.theme()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)

	var parts := UI.panel(2)
	var info: PanelContainer = parts[0]
	info.position = Vector2(12, 12)
	_hud.add_child(info)
	var box: VBoxContainer = parts[1]
	_title = UI.label("Działka", UI.GOLD)
	_title.add_theme_font_override("font", UI.bold())
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)
	_subtitle = UI.label("", UI.MUTED)
	box.add_child(_subtitle)
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	var name_label := UI.label(Game.character.get("name", ""))
	name_label.add_theme_font_override("font", UI.bold())
	level_row.add_child(name_label)
	_level = UI.label("", UI.GOLD)
	level_row.add_child(_level)
	box.add_child(level_row)
	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = "XpBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(200, 8)
	box.add_child(_xp_bar)
	_refresh_character()

	var money_parts := UI.panel(0)
	var money_panel: PanelContainer = money_parts[0]
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 6)
	money_row.add_child(UI.icon("coin", 22))
	_money = UI.label("", UI.GOLD)
	_money.add_theme_font_override("font", UI.bold())
	_money.add_theme_font_size_override("font_size", 17)
	money_row.add_child(_money)
	money_parts[1].add_child(money_row)
	_hud.add_child(money_panel)
	money_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	money_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# The tool in hand, bottom left.
	var tool_parts := UI.panel(2)
	var tool_panel: PanelContainer = tool_parts[0]
	var tool_label := UI.label("Narzędzie", UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	tool_label.add_theme_font_size_override("font_size", 12)
	tool_parts[1].add_child(tool_label)
	_tool_slot = ToolSlot.new()
	_tool_slot.changed.connect(_on_tool_changed)
	_tool_slot.failed.connect(_show_error)
	tool_parts[1].add_child(_tool_slot)
	_hud.add_child(tool_panel)
	tool_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	tool_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.add_child(UI.button("Ekwipunek  [I]", func() -> void:
		_inventory_window.toggle()
		if _inventory_window.visible:
			_reload_inventory()))
	bar.add_child(UI.button("Stacja  [T]", _go_to_station))
	_plant_button = UI.button("", func() -> void: _set_planting(not _planting))
	_plant_button.tooltip_text = "Sadzonki kupisz na rynku w garażu. Z każdego ściętego drzewa jest szansa na nową."
	bar.add_child(_plant_button)
	_update_plant_button()
	bar.add_child(UI.button("Mapa świata  [N]", Game.open_world_map))
	bar.add_child(UI.button("Garaż  [G]", Game.open_garage))
	_hud.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 10)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# The whole plot in small, bottom right.
	var map_parts := UI.panel(0)
	var map_panel: PanelContainer = map_parts[0]
	_minimap = TextureRect.new()
	_minimap.custom_minimum_size = Vector2(150, 150)
	_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	_minimap.tooltip_text = "Mapa działki: kliknij, aby tam pójść"
	_minimap.gui_input.connect(_on_minimap_input)
	map_parts[1].add_child(_minimap)
	_minimap_dot = ColorRect.new()
	(_minimap_dot as ColorRect).color = UI.GOLD
	_minimap_dot.size = Vector2(5, 5)
	_minimap_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.add_child(_minimap_dot)
	_hud.add_child(map_panel)
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_hint = _outlined(UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.size = Vector2(1280, 20)
	_hint.position = Vector2(0, 640)
	_hud.add_child(_hint)

	_prompt = _outlined(UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_prompt.visible = false
	_hud.add_child(_prompt)

	_field_label = _outlined(UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_field_label.add_theme_font_size_override("font_size", 14)
	_field_label.visible = false
	_hud.add_child(_field_label)

	_crop_menu = PopupMenu.new()
	_crop_menu.add_theme_constant_override("icon_max_width", 26)
	_crop_menu.id_pressed.connect(_on_crop_chosen)
	_crop_menu.popup_hide.connect(func() -> void:
		await get_tree().process_frame
		if not _crop_menu.visible:
			_menu_cell = Vector2i(-1, -1))
	_hud.add_child(_crop_menu)

	_object_menu = PopupMenu.new()
	_object_menu.id_pressed.connect(_on_object_chosen)
	_hud.add_child(_object_menu)

	_work_bar = ProgressBar.new()
	_work_bar.show_percentage = false
	_work_bar.step = 0.0
	_work_bar.custom_minimum_size = Vector2(70, 9)
	_work_bar.size = Vector2(70, 9)
	_work_bar.visible = false
	_work_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_work_bar)

	_toast = _outlined(UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_toast.size = Vector2(900, 30)
	_toast.position = Vector2(190, 600)
	_toast.modulate.a = 0.0
	_hud.add_child(_toast)

	_loading = UI.title("Wchodzę na działkę...", 22)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud.add_child(_loading)


func _outlined(label: Label) -> Label:
	label.add_theme_font_override("font", UI.bold())
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _refresh_character() -> void:
	var c := Game.character
	var xp: int = c.get("xp", 0)
	var level_xp: int = c.get("levelXp", 0)
	var next_xp: Variant = c.get("nextLevelXp")
	_level.text = "Poziom %d" % c.get("level", 1)
	_xp_bar.max_value = (next_xp - level_xp) if next_xp != null else 1.0
	_xp_bar.value = xp - level_xp if next_xp != null else 1.0
	_xp_bar.tooltip_text = "%d / %d XP" % [xp, next_xp] if next_xp != null else "%d XP" % xp


func _on_tool_changed() -> void:
	var held := Game.tool()
	_show_toast("W ręku: %s" % held["name"] if not held.is_empty() else "Narzędzie schowane do ekwipunku.")
	_update_hint()
	if _inventory_window.visible or _station_window.visible:
		_reload_inventory()


func _update_hint() -> void:
	var lines := {
		"tool_axe": "Kliknij drzewo, aby je ściąć siekierą.",
		"tool_pickaxe": "Kliknij kopalnię, aby wydobywać rudy, albo skałę, aby ją rozbić kilofem." if not _mines.is_empty() else "Kliknij skałę, aby ją rozbić kilofem.",
		"tool_shovel": "Kliknij wydmę, aby ją przekopać łopatą.",
		"tool_hoe": "Kliknij wolną ziemię, aby ją zaorać motyką, a pole, aby zasiać." if _fertile else "Motyką orze się tylko żyzne gleby.",
	}
	if _placing in MACHINERY:
		_hint.text = "Stawianie: kliknij wolne pole, aby postawić %s %s %s. [R] obraca, Esc kończy." % [
			_item_name(_placing).to_lower(), DIRECTION_ARROWS[_place_rotation], DIRECTIONS[_place_rotation]]
		return
	if _placing != "":
		_hint.text = "Stawianie: kliknij wolne pole, aby postawić %s. Esc anuluje." % _item_name(_placing).to_lower()
		return
	if _planting:
		_hint.text = "Sadzenie: kliknij wolne pole, aby posadzić sadzonkę (masz %d). [P] lub Esc kończy." % _saplings
		return
	var held: String = Game.tool().get("id", "")
	if held == "" and _fertile:
		lines[""] = "Kliknij pole, aby zasiać lub zebrać plony. Do orania weź motykę [Q]."
	_hint.text = lines.get(held, "Bez narzędzia nic tu nie zbierzesz. Narzędzia dostajesz za zakup działki w lesie, na pustyni, w górach lub na żyznych glebach.")
	_hint.text += "  ·  Stacja kolejowa [T] wysyła towary do innych fabryk."


func _set_balance(cents: int) -> void:
	_balance = cents
	_money.text = UI.money(cents)


# --- Minimap ------------------------------------------------------------------------------------------

func _build_minimap() -> void:
	_minimap_image = Image.create(_size, _size, false, Image.FORMAT_RGBA8)
	var floor_tint := Color(0.16, 0.16, 0.15)
	_minimap_image.fill(floor_tint)
	for y in _size:
		for x in _size:
			var kind := _tiles[y * _size + x]
			if kind != NONE and MINIMAP_COLORS.has(kind):
				_minimap_image.set_pixel(x, y, MINIMAP_COLORS[kind])
	for cell: Vector2i in _fields:
		_minimap_image.set_pixelv(cell, FIELD_COLOR)
	for cell: Vector2i in _trees:
		_minimap_image.set_pixelv(cell, MINIMAP_COLORS[TREE])
	# Mines stand out a little larger than they are, so they are easy to find.
	for mine: Dictionary in _mines.values():
		_minimap_image.fill_rect(Rect2i(int(mine["x"]) - 1, int(mine["y"]) - 1, int(mine["width"]) + 2, int(mine["height"]) + 2), MINIMAP_COLORS[MINE])
	_minimap.texture = ImageTexture.create_from_image(_minimap_image)
	# The plot is wider than tall on screen; keep the minimap's proportions the same.
	_minimap.custom_minimum_size = Vector2(170, 170 * TILE.y / TILE.x)


func _set_minimap(cell: Vector2i, kind: int) -> void:
	var colour: Color = MINIMAP_COLORS[kind] if kind != NONE else Color(0.16, 0.16, 0.15)
	if _trees.has(cell):
		colour = MINIMAP_COLORS[TREE]
	_minimap_image.set_pixelv(cell, FIELD_COLOR if _fields.has(cell) else colour)
	(_minimap.texture as ImageTexture).update(_minimap_image)


func _update_minimap_dot() -> void:
	var scale := _minimap.size / float(_size)
	_minimap_dot.position = _player.floor_pos * scale - _minimap_dot.size / 2


func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := Vector2i((event.position / _minimap.size * _size).floor())
		_stop_work()
		_walk_to(cell, Callable(), _solid(cell))


# --- Windows -----------------------------------------------------------------------------------------

func _build_windows() -> void:
	_inventory_window = GameWindow.new("Ekwipunek", 0)
	_inventory_window.position = Vector2(12, 150)
	_slots = InventoryGrid.new()
	_slots.hint = func(item: String) -> String:
		if item == "sapling":
			return "Kliknij, aby sadzić na działce"
		if PLACED_SPRITES.has(item) or item == BELT:
			return "Kliknij, aby postawić na działce"
		return "Kliknij, aby wziąć do ręki" if item in ToolSlot.TOOLS else ""
	_slots.clicked.connect(func(item: String) -> void:
		if item in ToolSlot.TOOLS:
			_tool_slot.equip(item)
		elif item == "sapling":
			_inventory_window.hide_window()
			_set_planting(true)
		elif PLACED_SPRITES.has(item) or item == BELT:
			_start_placing(item))
	_slots.changed.connect(func(items: Array) -> void:
		_items = items
		_count_saplings(items))
	_slots.failed.connect(_show_error)
	_inventory_window.content.add_child(_slots)
	_inventory_window.content.add_child(UI.label("Przeciągnij przedmiot na inny kafelek, aby zmienić kolejność.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_station_window = GameWindow.new("Stacja kolejowa", 430)
	_station_window.position = Vector2(1280 - 430 - 12, 64)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_station_box = VBoxContainer.new()
	_station_box.add_theme_constant_override("separation", 6)
	_station_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_station_box)
	_station_window.content.add_child(scroll)
	_crafting_window = CraftingWindow.new()
	_crafting_window.can_pick_up = true
	_crafting_window.position = Vector2(1280 - 400 - 12, 64)
	_crafting_window.finished.connect(_on_crafted)
	_crafting_window.inventory_changed.connect(_reload_inventory)
	_crafting_window.failed.connect(_show_error)
	_crafting_window.pick_up_requested.connect(_pick_up_placed)
	_furnace_window = FurnaceWindow.new()
	_furnace_window.can_pick_up = true
	_furnace_window.position = Vector2(1280 - 400 - 12, 64)
	_furnace_window.inventory_changed.connect(_on_furnace_changed)
	_furnace_window.failed.connect(_show_error)
	_furnace_window.pick_up_requested.connect(_pick_up_placed)
	_storage_window = StorageWindow.new()
	_storage_window.position = Vector2(1280 - 420 - 12, 64)
	_storage_window.inventory_changed.connect(func() -> void:
		_reload_inventory()
		_poll_logistics())
	_storage_window.failed.connect(_show_error)
	_storage_window.pick_up_requested.connect(_pick_up_placed)
	_splitter_window = SplitterWindow.new()
	_splitter_window.position = Vector2(1280 - 400 - 12, 64)
	_splitter_window.applied.connect(_logistics.apply)
	_splitter_window.failed.connect(_show_error)
	_machine_window = MachineWindow.new()
	_machine_window.position = Vector2(1280 - 420 - 12, 64)
	_machine_window.inventory_changed.connect(_on_furnace_changed)
	_machine_window.failed.connect(_show_error)
	_machine_window.pick_up_requested.connect(_pick_up_placed)
	var layer := _hud
	layer.add_child(_inventory_window)
	layer.add_child(_storage_window)
	layer.add_child(_splitter_window)
	layer.add_child(_station_window)
	layer.add_child(_crafting_window)
	layer.add_child(_furnace_window)
	layer.add_child(_machine_window)


func _reload_inventory() -> void:
	var reply := await Net.request("inventory.get")
	if reply["type"] != "inventory":
		return
	_items = reply["payload"]["items"]
	_count_saplings(_items)
	_slots.show_items(reply["payload"])
	_crafting_window.set_items(_items)
	_furnace_window.set_items(_items)
	_storage_window.set_items(_items)
	_splitter_window.set_items(_items)
	_machine_window.set_items(_items)
	if _station_window.visible and not _station_state.is_empty():
		_show_station()


func _refresh_station() -> void:
	var replies := [
		await Net.request("station.get", {"x": _at.x, "y": _at.y}),
		await Net.request("inventory.get"),
	]
	if replies[1]["type"] == "inventory":
		_items = replies[1]["payload"]["items"]
	_apply_station(replies[0])


func _apply_station(reply: Dictionary) -> void:
	if reply["type"] != "station":
		_show_error(reply)
		return
	_station_state = reply["payload"]
	_clock_offset = float(_station_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	_show_station()


func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _section(text: String) -> void:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	_station_box.add_child(l)


func _item_row(stack: Dictionary, quantity_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(stack["id"], 26))
	var name_label := UI.label(stack["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(UI.label(quantity_text, UI.MUTED))
	return row


func _show_station() -> void:
	for child in _station_box.get_children():
		child.free()
	_trip_labels.clear()
	var state := _station_state

	_section("Magazyn stacji")
	var stock: Array = state["items"]
	if stock.is_empty():
		_station_box.add_child(UI.label("Pusto. Załaduj towary z ekwipunku poniżej.", UI.MUTED))
	for stack: Dictionary in stock:
		var row := _item_row(stack, "× %d" % int(stack["quantity"]))
		row.add_child(UI.button("Do ekwipunku", _station_action.bind("station.unload", stack["id"], int(stack["quantity"]))))
		_station_box.add_child(row)

	_station_box.add_child(HSeparator.new())
	_section("Załaduj z ekwipunku")
	var loadable := 0
	for stack: Dictionary in _items:
		var item: String = stack["id"]
		if item.begins_with("furniture_"):
			continue
		loadable += 1
		var quantity := int(stack["quantity"])
		var row := _item_row(stack, "masz %d" % quantity)
		if quantity > 10:
			row.add_child(UI.button("10", _station_action.bind("station.load", item, 10)))
		row.add_child(UI.button("Wszystko", _station_action.bind("station.load", item, quantity)))
		_station_box.add_child(row)
	if loadable == 0:
		_station_box.add_child(UI.label("Ekwipunek jest pusty.", UI.MUTED))

	_station_box.add_child(HSeparator.new())
	_section("Wyślij pociąg")
	_build_send_form(stock)

	var incoming: Array = state["incoming"]
	var outgoing: Array = state["outgoing"]
	if not incoming.is_empty() or not outgoing.is_empty():
		_station_box.add_child(HSeparator.new())
		_section("W drodze")
	for trip: Dictionary in outgoing:
		_trip_row(trip, "→ %d × %d" % [int(trip["toX"]), int(trip["toY"])])
	for trip: Dictionary in incoming:
		_trip_row(trip, "← z %d × %d" % [int(trip["fromX"]), int(trip["fromY"])])
	_update_trips()


func _trip_row(trip: Dictionary, route: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(trip["item"], 22))
	var text := UI.label("%d × %s  %s" % [int(trip["quantity"]), trip["name"], route])
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	row.add_child(text)
	var left := UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	left.custom_minimum_size.x = 56
	row.add_child(left)
	_station_box.add_child(row)
	_trip_labels.append([left, float(trip["arrivesAt"])])


func _update_trips() -> void:
	if _station_state.is_empty():
		return
	var now := _server_now()
	for entry: Array in _trip_labels:
		var label: Label = entry[0]
		if is_instance_valid(label):
			var seconds := ceili(maxf(entry[1] - now, 0.0) / 1000.0)
			label.text = "%d:%02d" % [seconds / 60, seconds % 60] if seconds > 0 else "na miejscu"
	# Ask for the station again when a train has arrived.
	for trip: Dictionary in _station_state.get("incoming", []):
		if float(trip["arrivesAt"]) <= now and now >= _next_station_poll and _station_window.visible:
			_next_station_poll = now + 1500.0
			_refresh_station()
			break


func _station_action(type: String, item: String, quantity: int) -> void:
	var reply := await Net.request(type, {"x": _at.x, "y": _at.y, "item": item, "quantity": quantity})
	if reply["type"] != "station":
		_show_error(reply)
		return
	var inventory := await Net.request("inventory.get")
	if inventory["type"] == "inventory":
		_items = inventory["payload"]["items"]
	_apply_station(reply)
	if _inventory_window.visible:
		_reload_inventory()


func _build_send_form(stock: Array) -> void:
	if stock.is_empty():
		_station_box.add_child(UI.label("Najpierw załaduj coś na stację.", UI.MUTED))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	_station_box.add_child(grid)

	grid.add_child(UI.label("Dokąd", UI.MUTED))
	_send_to = OptionButton.new()
	_send_to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for plot in _my_plots:
		if plot != _at:
			_send_to.add_item("Moja działka %d × %d" % [plot.x, plot.y])
			_send_to.set_item_metadata(_send_to.item_count - 1, plot)
	_send_to.add_item("Inna działka (podaj X i Y)")
	_send_to.set_item_metadata(_send_to.item_count - 1, null)
	_send_to.item_selected.connect(func(_i: int) -> void: _update_send())
	grid.add_child(_send_to)

	grid.add_child(UI.label("X, Y", UI.MUTED))
	var xy := HBoxContainer.new()
	_send_x = SpinBox.new()
	_send_x.max_value = _world_width - 1
	_send_x.value = _at.x
	_send_y = SpinBox.new()
	_send_y.max_value = 3000
	_send_y.value = _at.y
	for spin: SpinBox in [_send_x, _send_y]:
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(func(_v: float) -> void: _update_send())
		xy.add_child(spin)
	grid.add_child(xy)

	grid.add_child(UI.label("Towar", UI.MUTED))
	_send_item = OptionButton.new()
	for stack: Dictionary in stock:
		_send_item.add_icon_item(UI.texture("icons/" + ("item_" + stack["id"] if not stack["id"].begins_with("furniture_") else stack["id"])),
			"%s (%d)" % [stack["name"], int(stack["quantity"])])
		_send_item.set_item_metadata(_send_item.item_count - 1, stack)
	_send_item.add_theme_constant_override("icon_max_width", 22)
	_send_item.item_selected.connect(func(_i: int) -> void:
		_send_quantity.max_value = _send_stack()["quantity"]
		_send_quantity.value = _send_quantity.max_value
		_update_send())
	grid.add_child(_send_item)

	grid.add_child(UI.label("Ilość", UI.MUTED))
	_send_quantity = SpinBox.new()
	_send_quantity.min_value = 1
	_send_quantity.max_value = stock[0]["quantity"]
	_send_quantity.value = stock[0]["quantity"]
	_send_quantity.value_changed.connect(func(_v: float) -> void: _update_send())
	grid.add_child(_send_quantity)

	_send_info = UI.label("", UI.MUTED)
	_station_box.add_child(_send_info)
	_send_button = UI.button("Wyślij pociąg", _send, true)
	_station_box.add_child(_send_button)
	_update_send()


func _send_stack() -> Dictionary:
	return _send_item.get_item_metadata(_send_item.selected)


func _send_target() -> Vector2i:
	var chosen: Variant = _send_to.get_item_metadata(_send_to.selected)
	if chosen is Vector2i:
		return chosen
	return Vector2i(int(_send_x.value), int(_send_y.value))


## Distance, time and fee of the trip, as the server counts them (see RailRules).
func _update_send() -> void:
	var manual: bool = _send_to.get_item_metadata(_send_to.selected) == null
	_send_x.editable = manual
	_send_y.editable = manual
	var target := _send_target()
	if not manual:
		_send_x.set_value_no_signal(target.x)
		_send_y.set_value_no_signal(target.y)
	var dx := absi(target.x - _at.x)
	dx = mini(dx, _world_width - dx)
	var km := sqrt(float(dx * dx + (target.y - _at.y) * (target.y - _at.y))) * 5.0
	var rates: Dictionary = _station_state["rates"]
	var seconds := maxf(rates["minTripSeconds"], km / 100.0 * rates["secondsPer100Km"])
	var quantity := int(_send_quantity.value)
	var fee := int(rates["baseFeeCents"]) + ceili(km / 100.0 * quantity * float(rates["centsPerItemPer100Km"]))
	_send_info.text = "Odległość %s km  ·  w drodze %d:%02d  ·  opłata %s" % [
		_grouped(roundi(km)), int(seconds) / 60, int(seconds) % 60, UI.money(fee)]
	_send_button.disabled = target == _at or fee > _balance
	if fee > _balance:
		_send_info.text += "\nNie masz tyle pieniędzy."
	elif target == _at:
		_send_info.text += "\nTo jest ta sama stacja."


func _grouped(value: int) -> String:
	var text := str(value)
	var out := ""
	for i in text.length():
		if i > 0 and (text.length() - i) % 3 == 0:
			out += " "
		out += text[i]
	return out


func _send() -> void:
	var target := _send_target()
	var stack := _send_stack()
	_send_button.disabled = true
	var reply := await Net.request("station.send", {
		"x": _at.x, "y": _at.y, "toX": target.x, "toY": target.y,
		"item": stack["id"], "quantity": int(_send_quantity.value),
	})
	if reply["type"] != "station":
		_show_error(reply)
		_send_button.disabled = false
		return
	_show_toast("Pociąg z %d × %s odjechał do działki %d × %d." % [int(_send_quantity.value), stack["name"], target.x, target.y], UI.GOLD)
	_apply_station(reply)
	var wallet := await Net.request("wallet.get")
	if wallet["type"] == "wallet":
		_set_balance(int(wallet["payload"]["balanceCents"]))


# --- Server ---------------------------------------------------------------------------------------------

func _load() -> void:
	_at = Game.plot
	var info := await Net.request("world.info")
	var wallet := await Net.request("wallet.get")
	var plot := await Net.request("plot.enter", {"x": _at.x, "y": _at.y})
	for reply: Dictionary in [info, wallet, plot]:
		if reply["type"] == "error":
			_loading.text = Game.error_text(reply)
			await get_tree().create_timer(2.0).timeout
			Game.open_world_map()
			return
	_world_width = info["payload"]["width"]
	for biome: Dictionary in info["payload"]["biomes"]:
		_biome_names[int(biome["id"])] = biome["name"]
	for owned: Dictionary in info["payload"]["plots"]:
		_my_plots.append(Vector2i(owned["x"], owned["y"]))
	_set_balance(int(wallet["payload"]["balanceCents"]))
	_apply_plot(plot["payload"])
	_title.text = "Działka %d × %d" % [_at.x, _at.y]
	_subtitle.text = "%s  ·  5 × 5 km" % _biome_names.get(int(plot["payload"]["biome"]), "?")
	_update_hint()
	_loading.queue_free()
	_reload_inventory()
	# Orders made while the player was away land in the inventory now.
	_crafting_window.refresh()
	_poll_logistics()


# --- Effects ---------------------------------------------------------------------------------------------

func _float_text(text: String, color: Color, at: Vector2, delay := 0.0, item := "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item != "":
		var icon := UI.item_icon(item, 26)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var l := _outlined(UI.label(text, color))
	l.add_theme_font_size_override("font_size", 17)
	row.add_child(l)
	row.modulate.a = 0.0
	_hud.add_child(row)
	row.reset_size()
	# Lines shown one after another stack downwards, so they never cover each other.
	var start := _screen(at) + Vector2(-row.size.x / 2, -120 * _zoom + delay * 110)
	row.position = start
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(row, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(row, "position:y", start.y - 50, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(row, "modulate:a", 0.0, 0.4)
	tween.tween_callback(row.queue_free)


func _show_toast(text: String, color := UI.TEXT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _show_error(reply: Dictionary) -> void:
	_show_toast(Game.error_text(reply), UI.ERROR)
