extends Node3D
## Title screen for Little Buddy.
## Navigates to the Baby Room when available; otherwise shows a friendly
## "Coming soon!" message instead of crashing. This guard exists because
## baby_room.tscn is authored by a separate agent in parallel.

const BABY_ROOM_PATH := "res://scenes/baby_room/baby_room.tscn"

## Aimed in code rather than relying on a hand-written Transform3D in the .tscn,
## which previously had an inverted pitch and framed the backdrop off-screen.
const CAMERA_POSITION: Vector3 = Vector3(0.0, 1.6, 3.4)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 0.5, -0.5)

@onready var play_button: Button = %PlayButton
@onready var coming_soon_label: Label = %ComingSoonLabel


func _ready() -> void:
	var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)
		camera.current = true

	coming_soon_label.visible = false
	play_button.pressed.connect(_on_play_pressed)


func _on_play_pressed() -> void:
	if ResourceLoader.exists(BABY_ROOM_PATH):
		get_tree().change_scene_to_file(BABY_ROOM_PATH)
	else:
		coming_soon_label.visible = true
		play_button.disabled = true
