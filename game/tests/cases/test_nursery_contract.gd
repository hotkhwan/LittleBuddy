extends RefCounted
## Enforces the boundary documented in docs/NURSERY_SWAP_CONTRACT.md.
##
## The nursery art is meant to be swappable (Kenney Furniture Kit today, Tiny
## Treats "Playful Bedroom" later) WITHOUT touching gameplay. That only holds if
## the room scene stays pure set dressing. This case fails loudly if a
## replacement smuggles in a camera, a second light, something interactive, or a
## prop that intrudes into the volume the baby and props occupy -- all of which
## would otherwise surface as a confusing runtime bug rather than a test failure.

const NURSERY_PATH := "res://scenes/nursery/nursery_props.tscn"

## The volume gameplay owns: baby, bottle, teddy and spawned props live here.
const PLAY_MIN := Vector3(-0.8, 0.0, -0.4)
const PLAY_MAX := Vector3(0.8, 1.0, 0.8)

## Rendering features the mobile performance budget forbids.
const FORBIDDEN_ENV_FLAGS: Array[String] = [
	"sdfgi_enabled", "ssao_enabled", "ssil_enabled", "ssr_enabled",
	"glow_enabled", "volumetric_fog_enabled",
]


func test_name() -> String:
	return "nursery_contract"


func run():
	var failures: Array = []

	if not ResourceLoader.exists(NURSERY_PATH):
		# Not a failure: baby_room.gd guards this load and falls back to its own
		# geometry, so an absent nursery is a supported state.
		return failures

	var packed: Resource = load(NURSERY_PATH)
	if packed == null or not (packed is PackedScene):
		return ["%s exists but is not a PackedScene" % NURSERY_PATH]

	var root: Node = (packed as PackedScene).instantiate()
	if root == null:
		return ["%s failed to instantiate" % NURSERY_PATH]

	failures.append_array(_check_root_type(root))
	failures.append_array(_check_no_gameplay_nodes(root))
	failures.append_array(_check_single_light(root))
	failures.append_array(_check_environment(root))
	failures.append_array(_check_play_volume_clear(root))

	root.free()
	return failures


func _check_root_type(root: Node) -> Array:
	if not (root is Node3D):
		return ["nursery root must be a Node3D, got %s" % root.get_class()]
	return []


## Set dressing only. Gameplay owns cameras, interaction and UI.
func _check_no_gameplay_nodes(root: Node) -> Array:
	var failures: Array = []
	var banned := {
		"Camera3D": "baby_room.tscn owns framing",
		"Area3D": "gameplay owns interaction and drop zones",
		"RigidBody3D": "heavy physics is outside the mobile budget",
		"CanvasLayer": "gameplay owns all child-facing UI",
		"GPUParticles3D": "particles are outside the mobile budget",
		"CPUParticles3D": "particles are outside the mobile budget",
	}
	for node: Node in _walk(root):
		for cls: String in banned:
			if node.is_class(cls):
				failures.append("nursery contains a %s (%s) at '%s'"
						% [cls, banned[cls], node.name])
	return failures


func _check_single_light(root: Node) -> Array:
	var failures: Array = []
	var directional := 0
	var other := 0
	for node: Node in _walk(root):
		if node.is_class("DirectionalLight3D"):
			directional += 1
		elif node.is_class("OmniLight3D") or node.is_class("SpotLight3D"):
			other += 1
	if directional != 1:
		failures.append("nursery must supply exactly 1 DirectionalLight3D, found %d" % directional)
	if other != 0:
		failures.append("nursery must add no omni/spot lights, found %d" % other)
	return failures


func _check_environment(root: Node) -> Array:
	var failures: Array = []
	var found_env := false
	for node: Node in _walk(root):
		if not node.is_class("WorldEnvironment"):
			continue
		found_env = true
		var env: Variant = node.get("environment")
		if env == null:
			failures.append("WorldEnvironment has no Environment resource")
			continue
		for flag: String in FORBIDDEN_ENV_FLAGS:
			if bool(env.get(flag)):
				failures.append("Environment has forbidden '%s' enabled" % flag)
	if not found_env:
		failures.append("nursery must supply a WorldEnvironment")
	return failures


## Props must not sit where the baby and spawned objects go.
func _check_play_volume_clear(root: Node) -> Array:
	var failures: Array = []
	var play := AABB(PLAY_MIN, PLAY_MAX - PLAY_MIN)

	for node: Node in _walk(root):
		if not (node is MeshInstance3D):
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		# Local AABB composed through ancestor transforms up to the nursery root;
		# global_transform is unavailable outside a live tree.
		var world: AABB = _transform_to_root(mesh_instance, root) * mesh_instance.mesh.get_aabb()
		if not world.intersects(play):
			continue
		# Floors and rugs legitimately pass under the play volume; only flag props
		# that actually occupy it.
		if world.size.y <= 0.06 and world.position.y <= 0.06:
			continue
		failures.append("nursery prop '%s' intrudes into the play volume (%s)"
				% [mesh_instance.name, str(world)])
	return failures


func _transform_to_root(node: Node3D, root: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
