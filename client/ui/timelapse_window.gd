class_name TimelapseWindow
extends GameWindow
## The timelapse of a factory: each day someone walked onto the plot the server kept what stood on it,
## and this plays those days one after another as a map seen from above, from the first workbench on.

const PLAY_EVERY := 0.35
## Colours of objects on the map by what they are, the rest grey.
const COLORS := {
	"logistics_": Color("#d9a520"), "storage_": Color("#8b6b3d"), "power_": Color("#4fa3e0"), "decor_": Color("#e05a8a"),
}

var _map := TimelapseMap.new()
var _day := UI.label("", UI.GOLD)
var _slider := HSlider.new()
var _play := UI.button("▶ Odtwórz", _toggle_play, true)
var _frames: Array = []
var _playing := false
var _wait := 0.0


func _init() -> void:
	super("Timelapse fabryki", 560)
	var top := HBoxContainer.new()
	_day.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_day)
	top.add_child(_play)
	content.add_child(top)
	var holder := CenterContainer.new()
	holder.add_child(_map)
	content.add_child(holder)
	_slider.step = 1
	_slider.value_changed.connect(func(value: float) -> void: _show_frame(int(value)))
	content.add_child(_slider)
	content.add_child(UI.label("Każdego dnia, gdy ktoś wchodzi na działkę, zapisuje się jej widok. Wejdź jutro, a film wydłuży się o kolejny dzień.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	set_process(true)


func open(plot: Vector2i) -> void:
	var reply := await Net.request("timelapse.get", {"x": plot.x, "y": plot.y})
	if reply["type"] != "timelapse":
		return
	var t: Dictionary = reply["payload"]
	_frames = t["frames"]
	_map.size_tiles = maxi(int(t["size"]), 1)
	_slider.max_value = maxi(_frames.size() - 1, 0)
	_slider.value = 0
	_show_frame(0)
	set_title("Timelapse fabryki (%d dni)" % int(t["days"]))
	show_window()
	_playing = _frames.size() > 1
	_play.text = "❚❚ Pauza" if _playing else "▶ Odtwórz"


func _toggle_play() -> void:
	if _frames.size() < 2:
		return
	if not _playing and int(_slider.value) >= _frames.size() - 1:
		_slider.value = 0
	_playing = not _playing
	_play.text = "❚❚ Pauza" if _playing else "▶ Odtwórz"


func _show_frame(i: int) -> void:
	if _frames.is_empty():
		_day.text = "Jeszcze nic nie zapisano"
		_map.objects = []
		_map.queue_redraw()
		return
	var frame: Dictionary = _frames[clampi(i, 0, _frames.size() - 1)]
	var day: String = frame["day"]
	var parts := day.split("-")
	var objects: Array = frame["objects"]
	_day.text = "%s.%s.%s  ·  %d obiektów" % [parts[2], parts[1], parts[0], objects.size()]
	_map.objects = objects
	_map.queue_redraw()


func _process(delta: float) -> void:
	super(delta)
	if not _playing or not visible:
		return
	_wait += delta
	if _wait < PLAY_EVERY:
		return
	_wait = 0.0
	if int(_slider.value) >= _frames.size() - 1:
		_playing = false
		_play.text = "▶ Odtwórz"
		return
	_slider.value += 1


static func color_of(kind: String) -> Color:
	for prefix: String in COLORS:
		if kind.begins_with(prefix):
			return COLORS[prefix]
	return Color("#c8c4bb") if kind.begins_with("furniture_") else Color("#7d8a72")


## The plot from above: each object a square the size of its footprint.
class TimelapseMap:
	extends Control

	const SIDE := 480.0

	var size_tiles := 1
	var objects: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(SIDE, SIDE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(SIDE, SIDE)), Color("#26301f"))
		var cell := SIDE / size_tiles
		for o: Array in objects:
			var kind: String = o[0]
			var s := Footprints.size(kind)
			var low := Footprints.low(kind)
			var at := Vector2(float(o[1]) - low, float(o[2]) - low) * cell
			draw_rect(Rect2(at, Vector2(s, s) * cell).grow(-0.3), TimelapseWindow.color_of(kind))
