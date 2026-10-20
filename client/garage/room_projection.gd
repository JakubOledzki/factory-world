class_name RoomProjection
## Maps garage floor positions in metres to screen pixels and back, as the room was rendered
## (see tools/render_art.py): screen = origin + x * axisX + y * axisY + z * axisZ.

const LAYOUT_FILE := "res://art/garage/layout.json"

static var _layout: Dictionary
static var _origin: Vector2
static var _axis_x: Vector2
static var _axis_y: Vector2
static var _axis_z: Vector2


static func layout() -> Dictionary:
	if _layout.is_empty():
		_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE))
		var p: Dictionary = _layout["projection"]
		_origin = Vector2(p["origin"][0], p["origin"][1])
		_axis_x = Vector2(p["axisX"][0], p["axisX"][1])
		_axis_y = Vector2(p["axisY"][0], p["axisY"][1])
		_axis_z = Vector2(p["axisZ"][0], p["axisZ"][1])
	return _layout


static func to_screen(floor_pos: Vector2, height := 0.0) -> Vector2:
	layout()
	return _origin + _axis_x * floor_pos.x + _axis_y * floor_pos.y + _axis_z * height


## The floor point under a screen position.
static func to_floor(screen: Vector2) -> Vector2:
	layout()
	var basis := Transform2D(_axis_x, _axis_y, Vector2.ZERO)
	return basis.affine_inverse() * (screen - _origin)
