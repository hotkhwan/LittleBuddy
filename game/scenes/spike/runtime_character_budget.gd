extends Node3D
## Measures the runtime Little Buddy against the procedural baby it would replace.
## Temporary, dev-only. Headless:
##   Godot --headless --path game res://scenes/spike/runtime_character_budget.tscn --quit-after 200

const BabyScript := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")
const BabyViewScript := preload("res://scripts/baby/baby_view_3d.gd")


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		return
	print("\n=== Runtime Little Buddy: performance ===")

	var rigged := BabyScript.new()
	add_child(rigged)
	rigged.call("build")
	var r: Dictionary = rigged.call("describe_budget")

	var proc := BabyViewScript.new()
	add_child(proc)
	if proc.has_method("build"):
		proc.call("build")
	var p_tris: int = _count(proc)
	var p_mats: Array = []
	_materials(proc, p_mats)

	var tris: int = int(r.get("triangles", 0))
	var verts: int = int(r.get("vertices", 0))
	var tex: int = int(r.get("maxTextureSize", 0))
	# one RGBA8 map plus a full mip chain is 4/3 of the base level
	var tex_bytes: float = tex * tex * 4.0 * (4.0 / 3.0)

	print("  RIGGED runtime (babyLittleBuddy_v01)")
	print("    triangles        : %d" % tris)
	print("    vertices         : %d" % verts)
	print("    surfaces         : %d" % int(r.get("surfaces", 0)))
	print("    materials        : %d" % int(r.get("materials", 0)))
	print("    textures bound   : %d" % int(r.get("appliedTextures", 0)))
	print("    max texture      : %d x %d" % [tex, tex])
	print("    texture memory   : %.2f MB (RGBA8 + mips, uncompressed)" % (tex_bytes / 1048576.0))
	print("    skin / clips     : %s / %s"
		% [str(r.get("hasSkin", false)), str(r.get("animationClips", []))])

	print("  PROCEDURAL baby (BabyView3D, today's shipping character)")
	print("    triangles        : %d" % p_tris)
	print("    materials        : %d" % p_mats.size())
	print("    textures         : 0 (vertex-coloured primitives)")

	print("  DELTA")
	if p_tris > 0:
		print("    triangles        : %+d  (%.1fx)" % [tris - p_tris, float(tris) / float(p_tris)])
	print("    art bible budget : %d triangles (main character), infant cap 3000"
		% BabyScript.MAX_TRIANGLES)
	print("    over budget by   : %.1fx vs 4000, %.1fx vs 3000"
		% [float(tris) / 4000.0, float(tris) / 3000.0])
	print("    texture budget   : %d x %d  -> over by %.1fx per side"
		% [BabyScript.MAX_TEXTURE_SIZE, BabyScript.MAX_TEXTURE_SIZE,
			float(tex) / float(BabyScript.MAX_TEXTURE_SIZE)])

	print("  VALIDATION (the wrapper's own gate)")
	for reason in rigged.call("validation_failures"):
		print("    - %s" % str(reason))

	get_tree().quit(0)


func _count(node: Node) -> int:
	var total: int = 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += (indices.size() / 3) if indices.size() > 0 else (points.size() / 3)
	for c in node.get_children():
		total += _count(c)
	return total


func _materials(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in range(mesh.get_surface_count()):
			var m: Material = mesh.surface_get_material(s)
			if m != null and not out.has(m):
				out.append(m)
	for c in node.get_children():
		_materials(c, out)
