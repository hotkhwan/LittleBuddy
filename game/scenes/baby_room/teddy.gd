extends DraggableObject
class_name Teddy

## Draggable comfort object built from primitive meshes only (spheres for
## head/body/ears/snout). Dragging it into the `HugDropZone` (or simply
## tapping it) plays a happy baby reaction and speaks "Teddy!" (wiring done
## by baby_room.gd, which listens for `comforted`).
##
## Awards no stars and is not an activity -- `feedMilk` remains the only
## scored activity tonight.
##
## Drag mechanics (touch-follows-finger, latched pointer index, tap
## fallback, no RigidBody3D) all live in the shared `DraggableObject` base.
## Reachable via the same two input paths as MilkBottle: built-in Area3D
## physics picking (`input_event`) and baby_room.gd's explicit raycast
## fallback (`try_trigger_from_raycast`).

signal comforted

const FUR_COLOR: Color = Color(0.62, 0.42, 0.24)
const SNOUT_COLOR: Color = Color(0.82, 0.65, 0.45)

## Generously larger than the visual mesh -- measured to project to roughly
## 240x240px on-screen at the Baby Room's default camera framing and the
## project's 1366x1024 viewport (see agent report for the full calculation).
const COLLISION_RADIUS: float = 0.2


func _ready() -> void:
	super._ready()
	_build_visual()
	_build_collision()


## Called by baby_room.gd's explicit raycast fallback when the built-in
## physics-picking path misses. Only acts if no gesture is already in
## progress via the primary input path -- avoids ever double-triggering.
func try_trigger_from_raycast() -> void:
	if not drag_enabled or is_interaction_active():
		return
	_deliver_via_tap()


func _on_dropped_in_zone() -> void:
	comforted.emit()


## -- Construction (primitives only) --------------------------------------

func _make_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


func _make_sphere(radius: float, color: Color, local_position: Vector3) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	instance.mesh = mesh
	instance.material_override = _make_material(color)
	instance.position = local_position
	return instance


func _build_visual() -> void:
	add_child(_make_sphere(0.09, FUR_COLOR, Vector3(0.0, 0.14, 0.0)))
	add_child(_make_sphere(0.06, FUR_COLOR, Vector3(0.0, 0.24, 0.0)))
	add_child(_make_sphere(0.025, SNOUT_COLOR, Vector3(0.0, 0.225, 0.055)))
	add_child(_make_sphere(0.025, FUR_COLOR, Vector3(-0.045, 0.29, 0.0)))
	add_child(_make_sphere(0.025, FUR_COLOR, Vector3(0.045, 0.29, 0.0)))
	add_child(_make_sphere(0.045, FUR_COLOR, Vector3(-0.1, 0.1, 0.0)))
	add_child(_make_sphere(0.045, FUR_COLOR, Vector3(0.1, 0.1, 0.0)))


func _build_collision() -> void:
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = COLLISION_RADIUS
	collision.shape = shape
	collision.position = Vector3(0.0, 0.18, 0.0)
	add_child(collision)
