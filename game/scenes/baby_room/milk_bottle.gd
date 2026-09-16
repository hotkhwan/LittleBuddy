extends DraggableObject
class_name MilkBottle

## Draggable 3D milk bottle built from primitive meshes only
## (CylinderMesh body + CapsuleMesh neck/cap).
##
## Drag mechanics (touch-follows-finger via a stable per-drag plane, latched
## pointer index, tap fallback, no RigidBody3D) all live in the shared
## `DraggableObject` base. This script only owns:
##   - the primitive visuals/collision,
##   - the "dimmed when not accepting" material tint,
##   - what happens on a successful delivery (`delivered` + a quick scale
##     settle so the pickup tilt/scale from DraggableObject don't linger).
##
## Reachable via two independent input paths, both funnelling into the same
## delivery latch in the base class:
##   1. `input_event` fired by Godot's built-in 3D physics picking
##      (requires `Viewport.physics_object_picking = true`, enabled by
##      `baby_room.gd`).
##   2. `try_deliver_from_raycast()`, called by `baby_room.gd`'s explicit
##      `_unhandled_input` raycast fallback so a missed pick never leaves
##      the child stuck.

signal delivered

const MILK_COLOR: Color = Color(1.0, 1.0, 0.95)
const CAP_COLOR: Color = Color(0.85, 0.7, 0.5)
const DIMMED_ALPHA_MIX: float = 0.55
const SETTLE_DURATION_SEC: float = 0.25

## Generously larger than the visual mesh so small fingers get a comfortable
## grab target -- measured to project to roughly 240x300px on-screen at the
## Baby Room's default camera framing and the project's 1366x1024 viewport
## (see agent report for the full calculation).
const COLLISION_RADIUS: float = 0.2
const COLLISION_HEIGHT: float = 0.5

var _materials: Array = []


func _ready() -> void:
	super._ready()
	_build_visual()
	_build_collision()


func set_enabled(value: bool) -> void:
	super.set_enabled(value)
	for mat: StandardMaterial3D in _materials:
		mat.albedo_color = mat.albedo_color.lerp(Color(0.6, 0.6, 0.6), 0.0 if value else DIMMED_ALPHA_MIX)


## Called by baby_room.gd's explicit raycast fallback when the built-in
## physics-picking path misses. Only acts if no gesture is already in
## progress via the primary input path -- avoids ever double-delivering.
func try_deliver_from_raycast() -> void:
	if not drag_enabled or is_interaction_active():
		return
	_deliver_via_tap()


func _on_dropped_in_zone() -> void:
	_settle_after_delivery()
	delivered.emit()


func _settle_after_delivery() -> void:
	_kill_active_tween()
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE, SETTLE_DURATION_SEC)
	tween.parallel().tween_property(self, "rotation:z", 0.0, SETTLE_DURATION_SEC)


## -- Construction (primitives only) --------------------------------------

func _make_material(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	_materials.append(mat)
	return mat


func _build_visual() -> void:
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "BottleBody"
	var body_mesh: CylinderMesh = CylinderMesh.new()
	body_mesh.top_radius = 0.05
	body_mesh.bottom_radius = 0.06
	body_mesh.height = 0.16
	body.mesh = body_mesh
	body.material_override = _make_material(MILK_COLOR)
	body.position = Vector3(0.0, 0.08, 0.0)
	add_child(body)

	var neck: MeshInstance3D = MeshInstance3D.new()
	neck.name = "BottleNeck"
	var neck_mesh: CapsuleMesh = CapsuleMesh.new()
	neck_mesh.radius = 0.025
	neck_mesh.height = 0.08
	neck.mesh = neck_mesh
	neck.material_override = _make_material(CAP_COLOR)
	neck.position = Vector3(0.0, 0.19, 0.0)
	add_child(neck)


func _build_collision() -> void:
	# Generously larger than the visual mesh -- child-sized touch targets
	# matter more than visual precision.
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = COLLISION_RADIUS
	shape.height = COLLISION_HEIGHT
	collision.shape = shape
	collision.position = Vector3(0.0, 0.12, 0.0)
	add_child(collision)
