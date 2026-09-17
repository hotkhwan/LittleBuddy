extends RefCounted

## The art direction of the four rooms, enforced instead of remembered.
##
## `docs/ART_BIBLE.md` is LOCKED and its §12 acceptance checklist is a gate, but
## almost nothing in it had a guard. The rules here are the ones whose violation
## is *invisible until someone renders and looks* -- which is exactly the class of
## defect this phase spent its night finding:
##
##   * a lavender wardrobe that renders beige, because a VERTEX colour is not
##     converted from sRGB the way `albedo_color` is;
##   * a backwards-wound quad that is not invisible but lit from behind, so a
##     whole room comes back flat and dusty and every assertion still passes;
##   * a `sleep` clip that lays the child on the floor in front of the bed,
##     because the pose plays at the interaction point and nobody wrote down how
##     far the bed was from it.
##
## None of those can be caught by a screenshot diff and all of them can be caught
## by arithmetic, so they are caught here.
##
## What this file deliberately does NOT do is assert that the rooms look good.
## That judgement belongs to a person with the renders in front of them (§12:
## "Rendered and looked at"). This asserts the things that make looking
## *meaningful*.

const HouseLayout := preload("res://scripts/house/house_layout.gd")
const Kit := preload("res://scripts/house/prop_kit.gd")
const RoomProps := preload("res://scripts/house/room_props.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const RoomScript := preload("res://scripts/house/room.gd")
const ToddlerView := preload("res://scripts/character/toddler_view.gd")

const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"

## §10, frame budget, per room. Draw calls are the metric that matters, and
## because the whole house shares ONE material, mesh count IS draw calls.
const MAX_DRAW_CALLS: int = 220
const MAX_TRIANGLES: int = 30000

## §5. A hard 90-degree corner is "the single strongest 'this is a prototype'
## signal", so nothing in the kit is allowed to ship one.
const REQUIRED_BEVEL: float = 0.02

## §7. Roughness 0.85-1.0, metallic 0, and none of the forbidden maps.
const MIN_ROUGHNESS: float = 0.85

## Every §3 token, so a colour can be checked for membership.
const TOKENS: Array[String] = [
	"fff6e5", "9ac0d9", "ffc1cc", "a8e6cf", "ffd3b6", "d6c7f0", "59422b",
]


func get_name() -> String:
	return "art_rooms"


func run():
	var failures: Array = []
	failures += _test_every_room_is_within_budget()
	failures += _test_one_material_and_it_obeys_section_7()
	failures += _test_architecture_is_bevelled()
	failures += _test_room_colours_are_palette_tokens()
	failures += _test_every_taught_object_has_its_own_shape()
	failures += _test_the_sleep_pose_lands_on_the_bed()
	failures += _test_one_light_no_forbidden_effects()
	return failures


## -- Budgets -------------------------------------------------------------------

func _test_every_room_is_within_budget():
	var failures: Array = []
	for room_id: String in HouseLayout.room_ids():
		var room: Node3D = _room(room_id)
		var meshes: int = int(room.call("count_meshes"))
		var triangles: int = int(room.call("count_triangles"))
		if meshes > MAX_DRAW_CALLS:
			failures.append("%s draws %d meshes; ART_BIBLE.md section 10 caps a frame at %d"
					% [room_id, meshes, MAX_DRAW_CALLS])
		if meshes < 1:
			failures.append("%s built no geometry at all" % room_id)
		if triangles > MAX_TRIANGLES:
			failures.append("%s is %d triangles; section 10's hard ceiling is %d"
					% [room_id, triangles, MAX_TRIANGLES])
		# The shell, three pieces of furniture and two doors. Fewer means something
		# silently built nothing -- which is what a null mesh looks like.
		if meshes < 6:
			failures.append("%s has only %d meshes; it should have a shell, 3 furniture "
					% [room_id, meshes] + "and 2 doors")
		room.free()
	return failures


## -- Materials (section 7) -------------------------------------------------------

func _test_one_material_and_it_obeys_section_7():
	var failures: Array = []
	var material: StandardMaterial3D = Kit.material()
	if material == null:
		return ["the house kit has no material"]
	if material.roughness < MIN_ROUGHNESS:
		failures.append("house material roughness is %.2f; section 7 locks it to 0.85-1.0"
				% material.roughness)
	if material.metallic > 0.0:
		failures.append("house material is metallic; section 7 says 0.0 everywhere")
	if material.normal_enabled:
		failures.append("house material has a normal map; section 7 forbids them")
	if material.emission_enabled:
		failures.append("house material emits; section 7 forbids emission")
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		failures.append("house material is transparent; section 7 allows no alpha, "
				+ "and section 10 budgets zero transparent surfaces")
	if not material.vertex_color_use_as_albedo:
		failures.append("the house material no longer reads vertex colour, so every "
				+ "room would render white")

	# Every mesh in every room must share that one material, or the draw-call
	# arithmetic above is meaningless.
	var room: Node3D = _room(HouseLayout.BEDROOM)
	for child: Node in room.get_node("Geometry").get_children():
		if not (child is MeshInstance3D):
			continue
		if (child as MeshInstance3D).material_override != material:
			failures.append("%s does not use the shared house material" % child.name)
	room.free()
	return failures


## -- Bevels (section 5) ----------------------------------------------------------

## The rule, measured on real geometry rather than trusted: a 2 m wall generated
## by the kit must have vertices strictly inside every one of its corners. A hard
## box has exactly 8 distinct vertex positions; a bevelled one cannot.
func _test_architecture_is_bevelled():
	var failures: Array = []
	if Kit.BEVEL < 0.015 or Kit.BEVEL > 0.03:
		failures.append("the architectural bevel is %.3f m; section 5 asks for ~2 cm"
				% Kit.BEVEL)

	var tool: SurfaceTool = Kit.begin()
	Kit.box(tool, Transform3D.IDENTITY, Vector3(2.0, 2.0, 2.0), Palette.CREAM)
	var mesh: ArrayMesh = Kit.commit(tool)
	if mesh == null:
		return failures + ["the kit produced no mesh for a 2 m box"]
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var corners: int = 0
	var on_the_bevel: int = 0
	for vertex: Vector3 in vertices:
		if absf(vertex.x) > 0.999 and absf(vertex.y) > 0.999 and absf(vertex.z) > 0.999:
			corners += 1
		var inside: float = 1.0 - Kit.BEVEL
		if absf(absf(vertex.x) - inside) < 0.002 and absf(vertex.y) > 0.999:
			on_the_bevel += 1
	if corners > 0:
		failures.append("the kit still emits %d sharp box corners; section 5 requires "
				% corners + "every architectural edge to carry a visible bevel")
	if on_the_bevel == 0:
		failures.append("no vertex sits on the chamfer of a generated box, so the bevel "
				+ "is not actually being built")

	# Normals must be unit length and must agree with the winding, or a surface is
	# lit from behind -- see the class docs.
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	if normals.size() != vertices.size():
		failures.append("generated geometry is missing per-vertex normals")
	else:
		for index: int in range(0, vertices.size(), 3):
			var shading: Vector3 = normals[index] + normals[index + 1] + normals[index + 2]
			var geometric: Vector3 = (vertices[index + 1] - vertices[index]).cross(
					vertices[index + 2] - vertices[index])
			if geometric.length_squared() < 0.0000001:
				continue
			if geometric.dot(shading) > 0.0:
				failures.append("triangle %d is wound against its own normal; Godot "
						% (index / 3) + "would light that surface from behind")
				break
	return failures


## -- Colour (section 3) ----------------------------------------------------------

func _test_room_colours_are_palette_tokens():
	var failures: Array = []
	var allowed: Array = []
	for hex: String in TOKENS:
		var base: Color = Color.html(hex)
		allowed.append(base)
		allowed.append(Palette.light(base))
		allowed.append(Palette.deep(base))
	# The one extra §5 names by hex: the flat window sky.
	allowed.append(Kit.WINDOW_SKY)

	var named: Dictionary = {
		"floor": HouseLayout.floor_color(HouseLayout.BEDROOM),
		"wall": HouseLayout.WALL_COLOR,
		"door": HouseLayout.DOOR_COLOR,
		"wood": HouseLayout.WOOD_COLOR,
	}
	for room_id: String in HouseLayout.room_ids():
		named["%s dominant" % room_id] = HouseLayout.dominant_color(room_id)
		named["%s accent" % room_id] = HouseLayout.accent_color(room_id)
		for prop: Dictionary in HouseLayout.furniture(room_id):
			named["%s.%s" % [room_id, String(prop["targetId"])]] = prop["color"] as Color

	for label: String in named.keys():
		var color: Color = named[label]
		if Palette.is_black(color):
			failures.append("%s is pure black; section 3 bans #000000 everywhere" % label)
		if Palette.is_red(color):
			failures.append("%s reads as red; section 3 bans red" % label)
		var matched: bool = false
		for candidate: Color in allowed:
			if _close(color, candidate):
				matched = true
				break
		if not matched:
			failures.append("%s is #%s, which is not a section 3 token or one of its two "
					% [label, color.to_html(false)] + "documented steps (light/deep)")

	# §3's room-mood table, as data.
	var moods: Dictionary = {
		HouseLayout.BEDROOM: [Palette.LAVENDER, Palette.DUSTY_BLUE],
		HouseLayout.BATHROOM: [Palette.DUSTY_BLUE, Palette.MINT],
		HouseLayout.KITCHEN: [Palette.PEACH, Palette.MINT],
		HouseLayout.LIVING_ROOM: [Palette.PEACH, Palette.SOFT_PINK],
	}
	for room_id: String in moods.keys():
		var pair: Array = moods[room_id]
		if not _close(HouseLayout.dominant_color(room_id), pair[0] as Color):
			failures.append("%s's dominant colour does not match section 3's room-mood "
					% room_id + "table")
		if not _close(HouseLayout.accent_color(room_id), pair[1] as Color):
			failures.append("%s's accent colour does not match section 3's room-mood table"
					% room_id)
	return failures


## -- Recognition (section 6) -----------------------------------------------------

## "One object teaches one word. Two nouns must never share a shape." Enforced
## the only way arithmetic can: every furniture id must have its own authored
## builder, and the twelve resulting meshes must all differ.
func _test_every_taught_object_has_its_own_shape():
	var failures: Array = []
	var signatures: Dictionary = {}
	for room_id: String in HouseLayout.room_ids():
		for prop: Dictionary in HouseLayout.furniture(room_id):
			var target_id: String = String(prop["targetId"])
			var tool: SurfaceTool = Kit.begin()
			if not RoomProps.build(tool, target_id, room_id, prop["size"] as Vector3):
				failures.append("'%s' has no authored shape, so it would fall back to a "
						% target_id + "coloured box -- section 6's greybox failure exactly")
				continue
			var mesh: ArrayMesh = Kit.commit(tool)
			if mesh == null:
				failures.append("'%s' built an empty mesh" % target_id)
				continue
			var triangles: int = Kit.triangles(mesh)
			if triangles < 40:
				failures.append("'%s' is only %d triangles; section 10's floor for even a "
						% [target_id, triangles] + "small prop is 40")
			if triangles > 2000:
				failures.append("'%s' is %d triangles; section 10 caps furniture at 2,000"
						% [target_id, triangles])
			var signature: String = "%d" % triangles
			if signatures.has(signature):
				failures.append("'%s' and '%s' are the same shape; section 6: two nouns "
						% [target_id, String(signatures[signature])]
						+ "must never share a shape")
			signatures[signature] = target_id
	return failures


## -- The bed, from both ends -----------------------------------------------------

## `sleep` plays at the bed's interaction point, so the clip carries the offset
## from that point onto the mattress. This asserts the character's copy of those
## numbers still describes the bed the house actually builds -- which is the only
## thing stopping Little Buddy going back to sleeping on the floor.
func _test_the_sleep_pose_lands_on_the_bed():
	var failures: Array = []
	var bed: Dictionary = {}
	for prop: Dictionary in HouseLayout.furniture(HouseLayout.BEDROOM):
		if String(prop["targetId"]) == "bed":
			bed = prop
	if bed.is_empty():
		return ["the bedroom has no bed"]

	var centre: Vector3 = bed["position"]
	var stand: Vector3 = bed["stand"]
	var size: Vector3 = bed["size"]

	var forward: float = Vector2(stand.x - centre.x, stand.z - centre.z).length()
	if absf(forward - ToddlerView.SLEEP_FORWARD) > 0.02:
		failures.append("toddler_view.SLEEP_FORWARD is %.2f m but the bed's interaction "
				% ToddlerView.SLEEP_FORWARD
				+ "point is %.2f m from its centre; the sleep pose would land off the bed"
				% forward)
	if absf(HouseLayout.BED_LIE_FORWARD - forward) > 0.02:
		failures.append("house_layout.BED_LIE_FORWARD disagrees with the bed's own stand "
				+ "position")
	if absf(HouseLayout.BED_LIE_ALONG - ToddlerView.SLEEP_ALONG) > 0.02:
		failures.append("the house and the character disagree about how far along the bed "
				+ "a sleeping child lies")
	if absf(HouseLayout.BED_LIE_HEIGHT - ToddlerView.SLEEP_LIFT) > 0.02:
		failures.append("the house says the blanket is at %.2f m and the character lies "
				% HouseLayout.BED_LIE_HEIGHT
				+ "down at %.2f m" % ToddlerView.SLEEP_LIFT)

	# The lift must be at or above the mattress and below the headboard, or he is
	# either inside the bed or floating over it.
	var top: float = centre.y + size.y * 0.5
	if ToddlerView.SLEEP_LIFT < top - 0.14 or ToddlerView.SLEEP_LIFT > top + 0.14:
		failures.append("a sleeping child rests at %.2f m but the bed's top is %.2f m"
				% [ToddlerView.SLEEP_LIFT, top])

	# And he has to FIT: head to foot along the bed, from where his feet land.
	var half_length: float = size.z * 0.5
	# His feet land `BED_LIE_ALONG` toward the FOOT of the bed (+Z) and his head is
	# 0.85 m from them toward the headboard (-Z); see `toddler_view.SLEEP_BODY`.
	var feet: float = HouseLayout.BED_LIE_ALONG
	var head: float = feet - 0.85
	if head < -half_length or feet > half_length:
		failures.append("a 0.85 m child lying from %.2f to %.2f does not fit a bed that "
				% [head, feet] + "runs %.2f to %.2f" % [-half_length, half_length])

	# The bed must run along Z, or "head toward the headboard" is wrong: a lying
	# child's head points along his own +X, and he faces the bed across its short
	# side.
	if size.z <= size.x:
		failures.append("the bed is no longer longer along Z than along X, so a sleeping "
				+ "child would lie across it rather than along it")
	if absf(stand.z - centre.z) > 0.02:
		failures.append("the bed's interaction point is not on its centre line, so the "
				+ "sleep offset would put the child off to one side")
	return failures


## -- Lighting (section 7) --------------------------------------------------------

func _test_one_light_no_forbidden_effects():
	var failures: Array = []
	var text: String = _read(HOUSE_SCENE)
	if text.is_empty():
		return ["%s could not be read" % HOUSE_SCENE]

	if text.count('type="DirectionalLight3D"') != 1:
		failures.append("the house must have exactly one DirectionalLight3D (section 7, "
				+ "non-negotiable)")
	if not text.contains("shadow_enabled = true"):
		failures.append("the house light casts no shadows; section 7: 'Shadows are what "
				+ "ground objects on the floor'")

	# Section 7's forbidden list, as scene properties.
	for banned: String in [
		"sdfgi_enabled = true", "ssao_enabled = true", "ssil_enabled = true",
		"ssr_enabled = true", "glow_enabled = true", "volumetric_fog_enabled = true",
		"dof_blur_far_enabled = true", "dof_blur_near_enabled = true",
		"adjustment_enabled = true",
	]:
		if text.contains(banned):
			failures.append("the house environment sets `%s`; section 7 forbids it" % banned)

	if not text.contains("ambient_light_source = 2"):
		failures.append("the house has no explicit ambient colour; section 7 wants a high "
				+ "warm fill, and without it the dark side of every form goes muddy")
	return failures


## -- Helpers -------------------------------------------------------------------

func _room(room_id: String) -> Node3D:
	var room := Node3D.new()
	room.set_script(RoomScript)
	room.set("room_id", room_id)
	room.call("build")
	return room


func _close(a: Color, b: Color) -> bool:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) <= 0.004


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
