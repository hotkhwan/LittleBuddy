extends SceneTree

func _initialize() -> void:
	var View := load("res://scripts/character/toddler_view.gd")
	var view: Node3D = View.new()
	root.add_child(view)
	view.call("build")
	print("tris = ", view.call("count_triangles"))
	var player: AnimationPlayer = view.call("get_animation_player")
	var names: Array = []
	for n in player.get_animation_list():
		names.append(n)
	names.sort()
	print("clips = ", names)
	# Every track path must resolve against the AnimationPlayer's root node.
	var bad: Array = []
	for n in player.get_animation_list():
		var a: Animation = player.get_animation(n)
		for t in range(a.get_track_count()):
			var p: NodePath = a.track_get_path(t)
			var node: Node = view.get_node_or_null(NodePath(String(p).get_slice(":", 0)))
			if node == null:
				bad.append("%s -> %s" % [n, String(p)])
	print("unresolved tracks = ", bad)
	# Mouth geometry: the centre must sit LOWER than the corners.
	var m: Node3D = view.get_node("Body/Torso/Head/Mouth")
	print("mouth centre y=%.4f left y=%.4f right y=%.4f" % [
		(m.get_node("Centre") as Node3D).position.y,
		(m.get_node("CornerLeft") as Node3D).position.y,
		(m.get_node("CornerRight") as Node3D).position.y])
	# Height check.
	var aabb: AABB = _aabb(view, view)
	print("aabb pos=", aabb.position, " size=", aabb.size)
	print("mesh count = ", _meshes(view))
	quit(0)

func _meshes(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _meshes(ch)
	return c

func _aabb(n: Node, rootn: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in _all(n):
		var a: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = (rootn as Node3D).global_transform.affine_inverse() * (mi as Node3D).global_transform
		var b: AABB = xf * a
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out

func _all(n: Node) -> Array:
	var r: Array = []
	if n is MeshInstance3D:
		r.append(n)
	for ch in n.get_children():
		r.append_array(_all(ch))
	return r
