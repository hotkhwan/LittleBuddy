extends Node3D
## Validation harness for the RUNTIME Little Buddy (rigged, weight-repaired).
##
## Temporary. Nothing in production references this. It exercises the wrapper the
## way the game will: semantic sockets, the action vocabulary, walk/run playback,
## and the measured budget.
##
## Headless:
##   Godot --headless --path game res://scenes/spike/runtime_character_validation.tscn --quit-after 300
## Visual: open the scene. Socket markers are drawn.

const BabyScript := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")

const SEMANTIC_SOCKETS: Array[String] = [
	"head", "mouth", "leftHand", "rightHand", "chest", "hugTarget",
]

var _baby: Node3D


func _ready() -> void:
	_baby = BabyScript.new()
	_baby.name = "BabyLittleBuddy"
	add_child(_baby)
	_baby.call("build")

	if DisplayServer.get_name() == "headless":
		_report()
		return
	_show_socket_markers()
	_baby.call("play_action", "walk")


func _report() -> void:
	var fails: int = 0
	print("\n=== Runtime Little Buddy validation ===")

	var pose: String = String(_baby.call("get_pose"))
	print("  pose on screen        : %s" % pose)
	if pose != "rigged":
		print("    FAIL: expected the rigged model to win pose resolution")
		fails += 1

	var budget: Dictionary = _baby.call("describe_budget")
	print("  triangles             : %d" % int(budget.get("triangles", 0)))
	print("  vertices              : %d" % int(budget.get("vertices", 0)))
	print("  surfaces / materials  : %d / %d"
		% [int(budget.get("surfaces", 0)), int(budget.get("materials", 0))])
	print("  max texture size      : %d" % int(budget.get("maxTextureSize", 0)))
	print("  hasSkin               : %s" % str(budget.get("hasSkin", false)))
	print("  animationClips        : %s" % str(budget.get("animationClips", [])))
	print("  metallic (asset)      : %.2f   applied %.2f"
		% [float(budget.get("metallic", -1)), float(budget.get("appliedMetallic", -1))])
	print("  hasNormalMap (asset)  : %s" % str(budget.get("hasNormalMap", false)))
	print("  doubleSided (asset)   : %s" % str(budget.get("doubleSided", true)))
	print("  rawHeight             : %.4f" % float(budget.get("rawHeight", 0.0)))
	print("  appliedScale          : %.5f" % float(budget.get("appliedScale", 0.0)))
	print("  placedHeight (metres) : %.4f" % float(budget.get("placedHeight", 0.0)))
	print("  characterHeight       : %.4f" % float(budget.get("characterHeight", 0.0)))
	print("  restingY              : %.5f" % float(budget.get("restingY", 0.0)))

	if not bool(budget.get("hasSkin", false)):
		print("    FAIL: no skin on the runtime model")
		fails += 1

	var placed: float = float(budget.get("placedHeight", 0.0))
	if absf(placed - 0.78) > 0.005:
		print("    FAIL: rendered height %.4f is not the locked 0.78 m" % placed)
		fails += 1
	var resting: float = float(budget.get("restingY", 0.0))
	if absf(resting) > 0.002:
		print("    FAIL: feet are not on the floor (restingY %.4f)" % resting)
		fails += 1

	# Independent cross-check of the reported height, from a source that cannot
	# share the audit's arithmetic: the Head bone sits at 48% of this character's
	# height (measured from the silhouette), so its resolved world Y must agree
	# with 0.78 m. This is what catches a unit-scale mistake in the chain.
	var head_y: float = (_baby.call("get_socket", "head") as Node3D).global_position.y
	var implied: float = head_y / 0.48
	print("  head socket Y         : %.4f  -> implies character height %.4f" % [head_y, implied])
	if absf(implied - 0.78) > 0.08:
		print("    FAIL: socket heights disagree with a 0.78 m character")
		fails += 1

	# sockets
	var resolved: Array = _baby.call("available_sockets")
	print("  sockets resolved      : %s" % str(resolved))
	for socket_name: String in SEMANTIC_SOCKETS:
		if not bool(_baby.call("has_socket", socket_name)):
			print("    FAIL: socket '%s' did not resolve" % socket_name)
			fails += 1
	for alias: String in ["MouthMarker", "HugMarker"]:
		if not bool(_baby.call("has_socket", alias)):
			print("    FAIL: legacy alias '%s' did not resolve" % alias)
			fails += 1

	# sockets must be distinct points, not all collapsed onto the origin
	var mouth: Vector3 = _baby.call("get_mouth_position")
	var hug: Vector3 = _baby.call("get_hug_position")
	var head: Vector3 = (_baby.call("get_socket", "head") as Node3D).global_position
	var lh: Vector3 = (_baby.call("get_socket", "leftHand") as Node3D).global_position
	var rh: Vector3 = (_baby.call("get_socket", "rightHand") as Node3D).global_position
	print("  mouth   %s" % str(mouth))
	print("  hug     %s" % str(hug))
	print("  head    %s" % str(head))
	print("  lHand   %s   rHand %s" % [str(lh), str(rh)])
	if mouth.distance_to(Vector3.ZERO) < 0.05:
		print("    FAIL: mouth collapsed to the character origin")
		fails += 1
	# An offset socket that landed on its parent bone means the offset was
	# expressed in the wrong units -- bone space here is centimetres, so a
	# metre-scale offset moves it by ~1 mm. Caught by distance, not by eye.
	if mouth.distance_to(head) < 0.05:
		print("    FAIL: mouth collapsed onto the head bone (offset units wrong?)")
		fails += 1
	# The mouth belongs on the face, not at the base of the skull where the Head
	# bone sits. The band is 55-80% of character height: the painted lips profile
	# at 61-63% in texture space, and the socket was settled at 58% by rendering
	# it -- a tighter band would be asserting the render-tuned figure back at
	# itself rather than catching a socket that has drifted off the face.
	if mouth.y < 0.78 * 0.55 or mouth.y > 0.78 * 0.80:
		print("    FAIL: mouth Y %.3f is not at face height (expected %.2f..%.2f)"
			% [mouth.y, 0.78 * 0.55, 0.78 * 0.80])
		fails += 1
	# "In front" is -Z here: the GLB is authored facing +Z, and the wrapper turns
	# it 180 degrees so yaw 0 faces -Z, which is the convention every other
	# character in the project follows. Asserting +Z would be asserting the raw
	# asset's convention rather than the game's.
	if mouth.z >= head.z - 0.05:
		print("    FAIL: mouth is not in front of the head along -Z (mouth %.3f, head %.3f)"
			% [mouth.z, head.z])
		fails += 1
	if lh.distance_to(rh) < 0.05:
		print("    FAIL: hands are at the same point")
		fails += 1
	if mouth.y < hug.y:
		print("    FAIL: mouth is below the hug target")
		fails += 1

	# actions
	for action: String in ["walk", "run"]:
		var can: bool = bool(_baby.call("can_play_action", action))
		print("  can_play_action(%s) : %s" % [action, str(can)])
		if not can:
			print("    FAIL: rigged model cannot play '%s'" % action)
			fails += 1

	print("=== %s ===\n" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)


func _show_socket_markers() -> void:
	for socket_name: String in SEMANTIC_SOCKETS:
		var node: Node3D = _baby.call("get_socket", socket_name)
		if node == _baby:
			continue
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.012
		sphere.height = 0.024
		mi.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.45, 0.1)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mi.material_override = mat
		node.add_child(mi)
