class_name PlotArt
## The pictures of plots in art/plot/. tools/render_plot_art.py stores them a few times bigger than
## they are drawn (twice, and machines that grow with their level more), so they stay sharp when the
## window or the camera zoom enlarges them; here they get back their size on screen, with mipmaps
## that keep them smooth when drawn smaller.

## How many times bigger than on screen a picture is stored, unless its layout says otherwise.
const SUPERSAMPLING := 2

static var _layout := {}
static var _textures := {}
static var _masks := {}


## Picture art/plot/<name>.png at its size on screen, `scale` times enlarged.
static func texture(name: String, scale := 1.0) -> Texture2D:
	var key := "%s@%s" % [name, scale]
	if not _textures.has(key):
		var image := _source(name)
		image.generate_mipmaps()
		var texture := ImageTexture.create_from_image(image)
		texture.set_size_override(Vector2i((Vector2(image.get_size()) * scale / _supersampling(name)).round()))
		_textures[key] = texture
	return _textures[key]


## The picture's pixels at its size on screen, `scale` times enlarged: what lies under the mouse.
static func mask(name: String, scale := 1.0) -> Image:
	var key := "%s@%s" % [name, scale]
	if not _masks.has(key):
		var image := _source(name)
		var size := (Vector2(image.get_size()) * scale / _supersampling(name)).round()
		image.resize(int(size.x), int(size.y), Image.INTERPOLATE_BILINEAR)
		_masks[key] = image
	return _masks[key]


static func _source(name: String) -> Image:
	var image: Image = load("res://art/plot/%s.png" % name).get_image()
	if image.is_compressed():
		image.decompress()
	return image


## A sprite's shadow is stored like the sprite.
static func _supersampling(name: String) -> int:
	if _layout.is_empty():
		_layout = JSON.parse_string(FileAccess.get_file_as_string("res://art/plot/layout.json"))
	var entry: Variant = _layout.get(name.trim_suffix("_shadow"))
	return int(entry.get("supersampling", SUPERSAMPLING)) if entry is Dictionary else SUPERSAMPLING
