extends RefCounted

## ============================================================================
## ALIZ'S FACE -- moods and blinks as texture patches, because her atlas is
## fragmented and her rig has no face bones.
## ============================================================================
##
## The same idea as `baby_face_moods.gd`, with one difference forced by the
## asset: Bunny's eyes and mouth each sit in one atlas rectangle, so his moods
## are PAINTED at runtime; Aliz's remeshed atlas spreads her mouth over three
## islands and her eyes over four, so no runtime rectangle can address a
## feature. Her moods are therefore painted OFFLINE in model metres by
## `tools/aliz_face_pass.py` (through the same 3D -> texel map every Aliz
## repaint has used), diffed against the base atlas, and shipped as small RGBA
## patches -- alpha 255 only where a mood differs -- plus a manifest naming
## which patches make which mood.
##
## At runtime this file:
##
##   1. reads the albedo off the material and checks the manifest's probe
##      texels against it (a re-export that moved the islands fails here and
##      the face system stands down, which is a smaller feature rather than a
##      smile on an ear);
##   2. keeps ONE working copy of the atlas as an `ImageTexture` on the
##      material;
##   3. on every change, copies the base and `blend_rect`s the active layers
##      on. That is one memcpy and a few hundred thousand texel writes, a
##      handful of times a minute -- a blink is two of them.
##
## ## What this is not
##
## Not facial animation: nothing interpolates, nothing runs per frame. Not a
## shader. Not a second material. The mesh, the skin weights and the clips are
## untouched; `test_buddy_avatar.gd`'s budgets are unaffected because the patch
## textures are never bound to a surface -- they are read once into RAM and
## composited on the CPU.
##
## ## Public surface (used by `pink_girl_buddy.gd`, never directly by gameplay)
##
##   `setup(material, manifest_path) -> bool`  bind to a material's albedo
##   `is_ready() -> bool`
##   `moods() -> Array[String]`                 the manifest's mood names
##   `blink_layer() -> String`
##   `show(mood, eyes_closed) -> bool`          compose and upload
##   `current_mood() -> String`, `eyes_closed() -> bool`
##   `mood_closes_eyes(mood) -> bool`       the mood itself shuts the eyes
##   `layer_rect(name) -> Rect2i`              for tests: where a layer writes
##   `canvas() -> Image`                        for tests: the atlas as shown

const MOOD_CONTENT: String = "content"

## How far a probe texel may drift from the manifest before the atlas is
## declared "not the one these patches were painted for". Per channel, 0-255.
## Lossless import means the real drift is 0; 20 leaves room for a colour
## management pass without letting a different unwrap through.
const PROBE_TOLERANCE: int = 20

var _manifest: Dictionary = {}
var _dir: String = ""
var _base: Image = null
var _canvas: Image = null
var _texture: ImageTexture = null
var _layers: Dictionary = {}
var _mood: String = MOOD_CONTENT
var _eyes_closed: bool = false
var _composed_once: bool = false


## Binds to `material`'s albedo. Returns false, and touches nothing, when the
## manifest is missing, the albedo cannot be read back, or the probes fail.
func setup(material: StandardMaterial3D, manifest_path: String) -> bool:
	if material == null or material.albedo_texture == null:
		return false
	_manifest = _read_manifest(manifest_path)
	if _manifest.is_empty():
		return false
	_dir = manifest_path.get_base_dir()
	var source: Image = material.albedo_texture.get_image()
	if source == null:
		return false
	if source.is_compressed():
		if source.decompress() != OK or source.is_compressed():
			return false
	var atlas: Array = _manifest.get("atlas", [])
	if atlas.size() != 2 or source.get_width() != int(atlas[0]) \
			or source.get_height() != int(atlas[1]):
		return false
	if not _probes_match(source):
		return false
	# RGBA so `blend_rect` accepts the RGBA patches; the alpha channel is inert
	# because the material's transparency is disabled.
	_base = source.duplicate()
	if _base.get_format() != Image.FORMAT_RGBA8:
		_base.convert(Image.FORMAT_RGBA8)
	_canvas = _base.duplicate()
	_texture = ImageTexture.create_from_image(_canvas)
	material.albedo_texture = _texture
	_mood = MOOD_CONTENT
	_eyes_closed = false
	return true


func is_ready() -> bool:
	return _texture != null


func moods() -> Array:
	var out: Array = []
	if _manifest.is_empty():
		return out
	for mood: String in (_manifest.get("moods", {}) as Dictionary).keys():
		out.append(mood)
	return out


func blink_layer() -> String:
	return String(_manifest.get("blinkLayer", ""))


func current_mood() -> String:
	return _mood


## Does `mood` itself include the blink layer (eyes shut as part of the mood)?
func mood_closes_eyes(mood: String) -> bool:
	var layers: Array = (_manifest.get("moods", {}) as Dictionary).get(mood, [])
	var blink: String = blink_layer()
	return not blink.is_empty() and layers.has(blink)


## True when the eyes are shut on the atlas -- by a blink, or because the mood
## itself shuts them (`sleepy`).
func eyes_closed() -> bool:
	return _eyes_closed or mood_closes_eyes(_mood)


## Composes `mood` (plus the blink layer when `eyes_closed`) onto the base and
## uploads it. Idempotent: the same request twice does no work the second time.
func show(mood: String, closed: bool) -> bool:
	if _texture == null:
		return false
	var moods_table: Dictionary = _manifest.get("moods", {})
	if not moods_table.has(mood):
		return false
	if mood == _mood and closed == _eyes_closed and _canvas != null and _composed_once:
		return true
	var names: Array = (moods_table[mood] as Array).duplicate()
	var blink: String = blink_layer()
	if closed and not blink.is_empty() and not names.has(blink):
		names.append(blink)
	_canvas.copy_from(_base)
	for name: String in names:
		var layer: Image = _layer(String(name))
		if layer == null:
			continue
		var rect: Rect2i = layer_rect(String(name))
		_canvas.blend_rect(layer, Rect2i(Vector2i.ZERO, layer.get_size()), rect.position)
	if _canvas.has_mipmaps():
		_canvas.generate_mipmaps()
	_texture.update(_canvas)
	_mood = mood
	_eyes_closed = closed
	_composed_once = true
	return true



func layer_rect(name: String) -> Rect2i:
	var spec: Dictionary = (_manifest.get("layers", {}) as Dictionary).get(name, {})
	var rect: Array = spec.get("rect", [])
	if rect.size() != 4:
		return Rect2i()
	return Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))


func canvas() -> Image:
	return _canvas


## A layer's patch, read once and kept. Null when the file is absent or is not
## the RGBA image the manifest promised, in which case that layer is simply
## skipped -- a mood missing one of its parts is still a better answer than an
## exception on a device.
func _layer(name: String) -> Image:
	if _layers.has(name):
		return _layers[name]
	var spec: Dictionary = (_manifest.get("layers", {}) as Dictionary).get(name, {})
	var path: String = _dir.path_join(String(spec.get("file", "")))
	var image: Image = null
	if ResourceLoader.exists(path):
		var texture: Texture2D = load(path) as Texture2D
		if texture != null:
			image = texture.get_image()
	if image != null and image.is_compressed():
		if image.decompress() != OK:
			image = null
	var rect: Rect2i = layer_rect(name)
	if image != null and image.get_size() != rect.size:
		push_warning("BuddyFace: layer '%s' is %s but the manifest says %s"
				% [name, str(image.get_size()), str(rect.size)])
		image = null
	if image != null and image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_layers[name] = image
	return image


func _probes_match(source: Image) -> bool:
	var probes: Array = _manifest.get("probes", [])
	if probes.is_empty():
		return false
	for probe: Dictionary in probes:
		var x: int = int(probe.get("x", -1))
		var y: int = int(probe.get("y", -1))
		var rgb: Array = probe.get("rgb", [])
		if x < 0 or y < 0 or x >= source.get_width() or y >= source.get_height() or rgb.size() != 3:
			return false
		var actual: Color = source.get_pixel(x, y)
		for channel: int in range(3):
			var expected: int = int(rgb[channel])
			var got: int = roundi(actual[channel] * 255.0)
			if absi(got - expected) > PROBE_TOLERANCE:
				return false
	return true


static func _read_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}
	var manifest: Dictionary = parsed
	if not manifest.has("layers") or not manifest.has("moods"):
		return {}
	return manifest
