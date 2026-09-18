extends Node3D
## TEMPORARY validation harness for the Meshy auto-rigged baby.
##
## Not production. Nothing here is referenced by a shipping scene, and the
## production Little Buddy is untouched. This exists to answer three questions
## before the rig is trusted:
##   1. does Godot import the skeleton, skin and clips at all?
##   2. do the LB_Rig_v1 sockets resolve to real bones?
##   3. do walk and run actually play?
##
## Run headless for a pass/fail report:
##   Godot --headless --path game --script res://scenes/spike/rig_validation.gd
## or open the scene for the visual check (socket markers are drawn).

const PROFILE_PATH := "res://content/rig_profiles/meshy_baby_v01.json"
const ASSET_DIR := "res://assets_source/meshy/littleBuddy/"
const RIGGED := ASSET_DIR + "babyStanding_rigged_v01.glb"
const CLIPS := {
	"walk": ASSET_DIR + "babyStanding_walk_v01.glb",
	"run": ASSET_DIR + "babyStanding_run_v01.glb",
}

var _profile: Dictionary = {}
var _players: Dictionary = {}     # clip name -> AnimationPlayer
var _current := "walk"
var _status: Label


func _ready() -> void:
	_profile = _load_profile()
	if _profile.is_empty():
		push_error("rig_validation: profile missing at %s" % PROFILE_PATH)
		if DisplayServer.get_name() == "headless":
			get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		_headless_report()
		return
	_build()
	_play(_current)


func _load_profile() -> Dictionary:
	if not ResourceLoader.exists(PROFILE_PATH) and not FileAccess.file_exists(PROFILE_PATH):
		return {}
	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _build() -> void:
	# bind pose on the left, walk in the middle, run on the right
	var layout := [
		{"name": "bind", "path": RIGGED, "x": -1.2},
		{"name": "walk", "path": CLIPS["walk"], "x": 0.0},
		{"name": "run", "path": CLIPS["run"], "x": 1.2},
	]
	for entry in layout:
		var inst := _spawn(entry["path"], entry["name"], entry["x"])
		if inst == null:
			continue
		if entry["name"] != "bind":
			var ap := _find_player(inst)
			if ap != null:
				_players[entry["name"]] = ap
	_build_ui()


func _spawn(path: String, label: String, x: float) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("rig_validation: missing %s (gitignored source asset)" % path)
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("rig_validation: could not load %s" % path)
		return null
	var inst: Node3D = packed.instantiate()
	inst.name = label
	# the rig is 1.7 units tall; scale it to a believable toddler for the view
	inst.scale = Vector3.ONE * 0.5
	inst.position = Vector3(x, 0.0, 0.0)
	add_child(inst)
	_attach_sockets(inst, label)
	return inst


## Resolve every LB_Rig_v1 socket onto the real skeleton via the RigProfile.
## A socket that cannot resolve is reported, never silently placed at the origin.
func _attach_sockets(root: Node3D, label: String) -> void:
	var skel := _find_skeleton(root)
	if skel == null:
		push_warning("rig_validation: no Skeleton3D under %s" % label)
		return
	var bone_map: Dictionary = _profile.get("boneMap", {})
	var offsets: Dictionary = _profile.get("socketOffsets", {})

	# direct bone sockets
	for socket in bone_map.keys():
		var bone_name: String = bone_map[socket]
		var idx := skel.find_bone(bone_name)
		if idx == -1:
			push_warning("rig_validation: socket '%s' -> bone '%s' NOT FOUND" % [socket, bone_name])
			continue
		var att := BoneAttachment3D.new()
		att.name = "socket_" + socket
		att.bone_name = bone_name
		skel.add_child(att)
		att.add_child(_marker(Color(0.2, 0.8, 1.0), socket))

	# offset sockets hang off an already-mapped bone
	for socket in offsets.keys():
		var spec: Dictionary = offsets[socket]
		var via: String = spec.get("bone", "")
		var bone_name: String = bone_map.get(via, "")
		if bone_name == "":
			push_warning("rig_validation: socket '%s' via unmapped '%s'" % [socket, via])
			continue
		var idx := skel.find_bone(bone_name)
		if idx == -1:
			push_warning("rig_validation: socket '%s' -> bone '%s' NOT FOUND" % [socket, bone_name])
			continue
		var att := BoneAttachment3D.new()
		att.name = "socket_" + socket
		att.bone_name = bone_name
		skel.add_child(att)
		var m := _marker(Color(1.0, 0.55, 0.1), socket)
		var off: Array = spec.get("offset", [0, 0, 0])
		m.position = Vector3(off[0], off[1], off[2])
		att.add_child(m)


func _marker(color: Color, label: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = "marker_" + label
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	holder.add_child(mi)
	return holder


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null


func _play(which: String) -> void:
	for key in _players.keys():
		var ap: AnimationPlayer = _players[key]
		var list := ap.get_animation_list()
		if list.is_empty():
			continue
		ap.play(list[0])
		ap.speed_scale = 1.0 if key == which else 1.0
	_current = which
	_refresh_ui()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(24, 24)
	_status.add_theme_font_size_override("font_size", 20)
	layer.add_child(_status)
	_refresh_ui()


func _refresh_ui() -> void:
	if _status == null:
		return
	var lines := ["Meshy rig validation  (TEMPORARY - not production)"]
	lines.append("left: bind pose   centre: walk   right: run")
	for key in _players.keys():
		var ap: AnimationPlayer = _players[key]
		var list := ap.get_animation_list()
		if list.is_empty():
			lines.append("%s: NO CLIPS" % key)
			continue
		var anim := ap.get_animation(list[0])
		lines.append("%s: '%s'  %.3fs" % [key, list[0], anim.length])
	lines.append("blue = bone sockets, orange = offset sockets")
	_status.text = "\n".join(lines)


## Headless report: prints pass/fail and exits non-zero on failure.
func _headless_report() -> void:
	var fails := 0
	print("\n=== Meshy rig validation (headless) ===")
	print("  profile loaded: %s" % _profile.get("profileId", "?"))

	for entry in [["rigged", RIGGED], ["walk", CLIPS["walk"]], ["run", CLIPS["run"]]]:
		var label: String = entry[0]
		var path: String = entry[1]
		if not ResourceLoader.exists(path):
			print("  FAIL: %s missing (%s)" % [label, path])
			fails += 1
			continue
		var packed: PackedScene = load(path)
		if packed == null:
			print("  FAIL: %s did not load" % label)
			fails += 1
			continue
		var inst: Node3D = packed.instantiate()
		var skel := _find_skeleton(inst)
		var ap := _find_player(inst)
		var bones := skel.get_bone_count() if skel != null else 0
		var clips: PackedStringArray = ap.get_animation_list() if ap != null else PackedStringArray()
		print("  %s: bones=%d  animationPlayer=%s  clips=%s"
			% [label, bones, str(ap != null), str(clips)])
		if skel == null:
			print("    FAIL: no Skeleton3D")
			fails += 1
		if label != "rigged":
			if clips.is_empty():
				print("    FAIL: no clips")
				fails += 1
			else:
				var a := ap.get_animation(clips[0])
				print("    clip length: %.3fs  tracks: %d" % [a.length, a.get_track_count()])
		# playback: the clip must actually MOVE the skeleton, not merely exist.
		# An AnimationPlayer with tracks that resolve to nothing still "plays".
		if label != "rigged" and ap != null and not clips.is_empty() and skel != null:
			add_child(inst)
			ap.play(clips[0])
			var a := ap.get_animation(clips[0])
			var samples: Array = []
			for frac in [0.0, 0.25, 0.5, 0.75]:
				ap.seek(a.length * frac, true)
				var pose: Array = []
				for b in skel.get_bone_count():
					pose.append(skel.get_bone_pose_position(b))
					pose.append(skel.get_bone_pose_rotation(b))
				samples.append(pose)
			var moved := 0
			for b in range(0, samples[0].size(), 2):
				var p0: Vector3 = samples[0][b]
				for s in range(1, samples.size()):
					if p0.distance_to(samples[s][b]) > 0.0001:
						moved += 1
						break
			var rotated := 0
			for b in range(1, samples[0].size(), 2):
				var q0: Quaternion = samples[0][b]
				for s in range(1, samples.size()):
					if absf(q0.dot(samples[s][b])) < 0.9999:
						rotated += 1
						break
			print("    playback: %d/%d bones translate, %d/%d rotate over the cycle"
				% [moved, skel.get_bone_count(), rotated, skel.get_bone_count()])
			if rotated == 0:
				print("    FAIL: clip plays but no bone actually moves")
				fails += 1
			remove_child(inst)

		# socket resolution
		if skel != null:
			var bone_map: Dictionary = _profile.get("boneMap", {})
			var missing: Array = []
			for socket in bone_map.keys():
				if skel.find_bone(bone_map[socket]) == -1:
					missing.append("%s->%s" % [socket, bone_map[socket]])
			if missing.is_empty():
				print("    sockets: all %d bone sockets resolved" % bone_map.size())
			else:
				print("    FAIL: unresolved sockets: %s" % str(missing))
				fails += 1
		inst.free()

	print("=== %s ===\n" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
