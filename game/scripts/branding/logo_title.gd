class_name LogoTitle
extends TextureRect

## The "Little Days" title lockup, as one drop-in node.
##
## ## For whoever places it in `main.tscn` (Agent B)
##
## Replace `UI/SafeArea/TitlePanel` (the cream panel with the 80 pt Label)
## with a `TextureRect` carrying this script. Nothing else is needed: the node
## loads its own texture, keeps the logo's aspect inside whatever rect it is
## given, and idles with a 3 degree sway. Suggested rect, in the 1366x1024
## design space, is the same slot the panel used but taller, because the logo
## carries Aliz and Bunny above the plaque:
##
## ```
## [node name="LogoTitle" type="TextureRect" parent="UI/SafeArea"]
## layout_mode = 1
## anchors_preset = -1
## anchor_left = 0.5
## anchor_right = 0.5
## offset_left = -230.0
## offset_top = 8.0
## offset_right = 230.0
## offset_bottom = 285.0
## grow_horizontal = 2
## mouse_filter = 2
## script = ExtResource("<logo_title.gd>")
## ```
##
## 460x277 is the 1024x616 texture at 45%, which keeps the plaque's letters
## about the size the old Label was and leaves the row from y=285 down to the
## characters. Any rect works; the logo is letterboxed inside it, centred.
##
## `set_compact(true)` is for phones: it swaps to the 512 texture and scales
## the sway down. Call it from the same place the menu already decides the
## phone layout (`SafeArea` insets or aspect > 1.9). Everything else is
## automatic. `is_processing()` gates the sway, so `set_process(false)` freezes
## the logo for a screenshot or a paused menu and `set_process(true)` resumes
## it from where it was.
##
## The version string does not live here. See `docs/patches/agentA_project_godot.diff`
## and the report for where `GameVersion.BUILD` goes (bottom-right, subtle).
##
## ## Why a script and not a texture in the .tscn
##
## The textures are loaded by path at runtime, not `preload()`ed, so a menu
## scene still parses and opens if a texture is ever moved or missing -- the
## node simply stays empty and the buttons underneath keep working. A missing
## title is a bug; a title screen that fails to open is a child with nothing.

const TEXTURE_PATH: String = "res://assets/branding/littleDaysLogo_1024.png"
const TEXTURE_COMPACT_PATH: String = "res://assets/branding/littleDaysLogo_512.png"

## The sway. Three degrees each way, a slow breath: present, never busy.
const SWAY_DEGREES: float = 3.0
const SWAY_PERIOD_SEC: float = 3.6
const COMPACT_SWAY_DEGREES: float = 2.0

var _compact: bool = false
var _sway_time: float = 0.0


func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Decorative: taps go through to whatever the menu puts underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_texture()
	pivot_offset = size * 0.5


func _ready() -> void:
	_recentre_pivot()
	if not resized.is_connected(_recentre_pivot):
		resized.connect(_recentre_pivot)
	# Ensure transforms are centred before the first draw notification, not one
	# idle frame after the container resolves this rect.
	call_deferred("_recentre_pivot")


func _process(delta: float) -> void:
	_sway_time = fmod(_sway_time + delta, SWAY_PERIOD_SEC)
	var degrees: float = COMPACT_SWAY_DEGREES if _compact else SWAY_DEGREES
	rotation = deg_to_rad(degrees) * sin(TAU * _sway_time / SWAY_PERIOD_SEC)


## Phone layout: the 512 texture and a smaller sway.
func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_load_texture()


func is_compact() -> bool:
	return _compact


## The rotation the sway would apply at `time` seconds, for tests.
func sway_at(time: float) -> float:
	var degrees: float = COMPACT_SWAY_DEGREES if _compact else SWAY_DEGREES
	return deg_to_rad(degrees) * sin(TAU * fmod(time, SWAY_PERIOD_SEC) / SWAY_PERIOD_SEC)


func _load_texture() -> void:
	var path: String = TEXTURE_COMPACT_PATH if _compact else TEXTURE_PATH
	if ResourceLoader.exists(path):
		texture = load(path)
	else:
		push_warning("LogoTitle: missing %s; the title stays empty" % path)
		texture = null


func _recentre_pivot() -> void:
	pivot_offset = size * 0.5
