extends Node3D
## Renders the App Store icon FROM THE REAL CHARACTERS. Dev tool, never shipped.
##
##   Godot --path game --resolution 1024x1024 res://scenes/spike/icon_render.tscn
##
## Writes `game/icon_1024.png`, then `tools/make_ios_icons.sh` cuts the rest.
##
## ## Why render the game rather than draw a logo
##
## The previous icon was a milk bottle: clean, generic, and nothing a child would
## connect to the app they played yesterday. The brief is explicit -- the icon
## should be the characters, so that the thing on the home screen is the thing in
## the game. Rendering the actual wrappers also means the icon cannot drift from
## the art: re-run it after a character change and it is right again.
##
## ## The composition rules, and why each one
##
## * **Two faces, large.** At 60x60 on a home screen a full body is a smudge.
##   The camera is tight on the heads and the bodies are allowed to run off the
##   bottom edge.
## * **The baby is lifted** to bring the two heads together. PinkGirl's head is
##   at 1.45 m and the baby's at 0.55 m; framing both full-length would put a
##   metre of empty dress between them. The lift is invisible at this crop and
##   reads as "held".
## * **No text.** Required by the brief, and correct: the name is under the icon
##   already.
## * **Pastel, low contrast, strong silhouette.** A warm cream field, one soft
##   disc behind the pair to separate them from it, and no shadows -- shadow
##   detail disappears at small sizes and only muddies the shape.

const BabyScript := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")
const BuddyScript := preload("res://scripts/characters/buddy/pink_girl_buddy.gd")
const Palette := preload("res://scripts/ui/palette.gd")

const OUT_PATH := "icon_1024.png"

## Lift applied to the baby so the two heads sit side by side.
const BABY_LIFT: float = 0.50
const BABY_OFFSET := Vector3(0.34, 0.0, 0.30)
const BUDDY_OFFSET := Vector3(-0.22, 0.0, 0.0)

var _settle := 0


## Everything is built INSIDE a fixed 1024x1024 `SubViewport` rather than being
## rendered at the window size. The window is clamped by the desktop -- asking
## for 1024x1024 produced a 1024x933 image, which is not an icon -- and a
## SubViewport is the only way to guarantee the aspect the App Store requires.
var _view: SubViewport = null


func _ready() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1024, 1024)
	_view.transparent_bg = false
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	# Move the authored environment, light and camera into the SubViewport so it
	# renders the same scene the .tscn describes.
	for child in [$WorldEnvironment, $Key, $Camera3D]:
		remove_child(child)
		_view.add_child(child)

	var buddy: Node3D = BuddyScript.new()
	_view.add_child(buddy)
	buddy.call("build")
	buddy.position = BUDDY_OFFSET
	buddy.rotation_degrees.y = 196.0

	var baby: Node3D = BabyScript.new()
	_view.add_child(baby)
	baby.call("build")
	baby.position = BABY_OFFSET + Vector3(0.0, BABY_LIFT, 0.0)
	baby.rotation_degrees.y = 170.0

	# Soft disc behind the pair: separates them from the field without adding a
	# hard edge that would alias at 60 px.
	var disc := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.95
	sphere.height = 1.90
	sphere.radial_segments = 48
	disc.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.PEACH
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.position = Vector3(0.14, 1.02, -1.30)
	disc.scale = Vector3(1.0, 1.0, 0.04)
	_view.add_child(disc)

	var camera: Camera3D = _view.get_node("Camera3D")
	camera.position = Vector3(0.12, 1.18, 1.76)
	camera.look_at(Vector3(0.12, 1.02, 0.0), Vector3.UP)
	camera.fov = 40.0
	_settle = 14


func _process(_d: float) -> void:
	if _settle <= 0:
		return
	_settle -= 1
	if _settle > 0:
		return
	await RenderingServer.frame_post_draw
	var image: Image = _view.get_texture().get_image()
	# App Store icons must be fully opaque; a stray alpha channel is a submission
	# rejection rather than a cosmetic problem.
	image.convert(Image.FORMAT_RGB8)
	var path: String = ProjectSettings.globalize_path("res://" + OUT_PATH)
	var err: int = image.save_png(path)
	print("%s icon -> %s (%dx%d)" % ["ok" if err == OK else "FAIL", path,
			image.get_width(), image.get_height()])
	get_tree().quit(0 if err == OK else 1)
