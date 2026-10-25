class_name WorldData
extends RefCounted
## The world map as plots of 5 × 5 km: the biome of every plot and the towns, read from the files
## made by tools/build_world.py. The grid is the Behrmann equal-area projection: column 0 starts at
## 180° W, row 0 is the North Pole, and the map wraps around east to west.

const BIOMES_FILE := "res://world/biomes.bin.gz"
const TOWNS_FILE := "res://world/towns.tsv.gz"

const RADIUS_KM := 6371.0072
const PLOT_KM := 5.0
## Towns are grouped in squares of this many plots, to find the ones on screen quickly.
const BUCKET := 64

## Biome ids, as on the server (World.Biome).
enum { OCEAN, LAKE, FOREST, FARMLAND, GRASSLAND, DESERT, MOUNTAINS, TUNDRA, ICE, CITY, COAST, LAKESHORE, OASIS }
## Of desert plots, this many in a hundred are oases; the server works it out the same way (Oasis.Is).
const OASIS_PERCENT := 4

## Map colours by biome id: forests dark green, deserts yellow, all muted for the dark style.
const COLORS: Array[Color] = [
	Color("#0b1620"), Color("#1d4257"), Color("#1f4a2b"), Color("#6f8a35"),
	Color("#a5a052"), Color("#d6ad52"), Color("#75624f"), Color("#7f8f86"),
	Color("#d9e3e8"), Color("#a39d9a"), Color("#3d8a84"), Color("#4f8fa8"),
	Color("#5f9a4a"),
]

var width := 0
var height := 0
var biomes := PackedByteArray()

## Towns, largest first: plot column and row, population and name.
var town_x := PackedInt32Array()
var town_y := PackedInt32Array()
var town_population := PackedInt32Array()
var town_names := PackedStringArray()
## Bucket index → Array of town indices in it, largest first.
var _buckets := {}
var _buckets_across := 0


func load_files() -> bool:
	var raw := _read_gzip(BIOMES_FILE)
	if raw.size() < 8 or raw.slice(0, 4).get_string_from_ascii() != "FWW1":
		push_error("World map file is missing or broken: %s" % BIOMES_FILE)
		return false
	width = raw.decode_u16(4)
	height = raw.decode_u16(6)
	biomes = raw.slice(8)
	_load_towns()
	return biomes.size() == width * height


func biome(plot: Vector2i) -> int:
	if plot.y < 0 or plot.y >= height:
		return OCEAN
	var x := posmod(plot.x, width)
	var id := biomes[plot.y * width + x]
	return OASIS if id == DESERT and is_oasis(x, plot.y) else id


## Whether the desert plot at (x, y) is an oasis: the same hash as the server's, in 64-bit integers.
static func is_oasis(x: int, y: int) -> bool:
	var h := (x * 374761393 + y * 668265263) & 0xffffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff
	h ^= h >> 16
	return h % 100 < OASIS_PERCENT


## Part of the map as a texture: one byte per plot, the biome id, for the map shader.
## Split in columns because some phones cannot hold a texture wider than 4096 pixels.
func texture(from_x: int, columns: int) -> ImageTexture:
	var image := Image.create_from_data(width, height, false, Image.FORMAT_R8, biomes)
	return ImageTexture.create_from_image(image.get_region(Rect2i(from_x, 0, columns, height)))


## Latitude and longitude, in degrees, of a point of the grid (in plots, fractions allowed).
func to_geo(point: Vector2) -> Vector2:
	var cos30 := cos(PI / 6)
	var lon := (point.x * PLOT_KM - width * PLOT_KM / 2.0) / (RADIUS_KM * cos30)
	var sin_lat := clampf((height * PLOT_KM / 2.0 - point.y * PLOT_KM) * cos30 / RADIUS_KM, -1.0, 1.0)
	return Vector2(rad_to_deg(asin(sin_lat)), wrapf(rad_to_deg(lon), -180.0, 180.0))


## The point of the grid, in plots, at a latitude and longitude in degrees.
func from_geo(lat: float, lon: float) -> Vector2:
	var cos30 := cos(PI / 6)
	return Vector2(
		(deg_to_rad(lon) * RADIUS_KM * cos30 + width * PLOT_KM / 2.0) / PLOT_KM,
		(height * PLOT_KM / 2.0 - RADIUS_KM * sin(deg_to_rad(lat)) / cos30) / PLOT_KM)


## "52,23° N  21,01° E"
static func geo_text(geo: Vector2) -> String:
	return "%s° %s  %s° %s" % [
		("%.2f" % absf(geo.x)).replace(".", ","), "N" if geo.x >= 0 else "S",
		("%.2f" % absf(geo.y)).replace(".", ","), "E" if geo.y >= 0 else "W"]


## Indices of towns with at least `min_population` in a rectangle of plots (columns may run past the
## map's edges; they wrap). Largest first within each bucket.
func towns_in(rect: Rect2i, min_population: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	var top := clampi(rect.position.y / BUCKET, 0, (height - 1) / BUCKET)
	var bottom := clampi(rect.end.y / BUCKET, 0, (height - 1) / BUCKET)
	var left := floori(float(rect.position.x) / BUCKET)
	var right := floori(float(rect.end.x) / BUCKET)
	for by in range(top, bottom + 1):
		for bx_raw in range(left, mini(right, left + _buckets_across - 1) + 1):
			var key := by * _buckets_across + posmod(bx_raw, _buckets_across)
			for i: int in _buckets.get(key, []):
				if town_population[i] < min_population:
					break
				found.append(i)
	return found


## The largest town within `radius` plots of a plot, or -1.
func nearest_town(plot: Vector2i, radius := 12) -> int:
	var best := -1
	var best_score := 0.0
	for i in towns_in(Rect2i(plot - Vector2i(radius, radius), Vector2i(radius, radius) * 2), 0):
		var distance := Vector2(wrap_dx(town_x[i] - plot.x), town_y[i] - plot.y).length()
		if distance > radius:
			continue
		# Prefer big towns, but a village next door beats a city at the edge of the radius.
		var score := log(float(town_population[i])) - distance * 0.6
		if best < 0 or score > best_score:
			best = i
			best_score = score
	return best


## Finds a town by name: an exact match (ignoring case) wins, then names that start with the text.
func find_town(text: String) -> int:
	var wanted := text.strip_edges().to_lower()
	if wanted.is_empty():
		return -1
	var prefix := -1
	for i in town_names.size():
		var name := town_names[i].to_lower()
		if name == wanted:
			return i
		if prefix < 0 and name.begins_with(wanted):
			prefix = i
	return prefix


## A column difference taken the short way round the globe.
func wrap_dx(dx: float) -> float:
	return wrapf(dx, -width / 2.0, width / 2.0)


func _load_towns() -> void:
	var lines := _read_gzip(TOWNS_FILE).get_string_from_utf8().split("\n", false)
	var count := lines.size()
	town_x.resize(count)
	town_y.resize(count)
	town_population.resize(count)
	town_names.resize(count)
	_buckets_across = ceili(float(width) / BUCKET)
	for i in count:
		var fields := lines[i].split("\t")
		town_x[i] = fields[0].to_int()
		town_y[i] = fields[1].to_int()
		town_population[i] = fields[2].to_int()
		town_names[i] = fields[3]
		var key := (town_y[i] / BUCKET) * _buckets_across + town_x[i] / BUCKET
		if not _buckets.has(key):
			_buckets[key] = []
		_buckets[key].append(i)


static func _read_gzip(path: String) -> PackedByteArray:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return bytes
	return bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
