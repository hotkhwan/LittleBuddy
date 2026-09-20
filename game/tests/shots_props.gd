extends SceneTree

## THE THINGS A CHILD PICKS UP, photographed and MEASURED.
##
##   Godot --path game --resolution 1334x750 --script res://tests/shots_props.gd -- ipad
##   Godot --path game --resolution 1334x750 --script res://tests/shots_props.gd -- iphone 2340x1080
##
## Three jobs, and the middle one is the reason this file is not just a camera:
##
##   1. **ITEMS** -- the seven kitchen props, side by side, built by the REAL
##      `kitchen_view.gd::_make_item()`, standing in the REAL kitchen under the
##      REAL single `DirectionalLight3D`. Judged on charm and on separation: two
##      nouns must not share a shape (`ART_BIBLE` §6).
##   2. **SILHOUETTE** -- the same row again with every mesh flooded to unshaded
##      `ink`. §2's silhouette test is "identifiable in pure black at 64 px", and
##      the only way to know is to render it flat. A shape that survives colour
##      being taken away is a shape a child can name.
##   3. **FLOAT AUDIT** -- every prop the game ever puts down, measured against
##      the surface it claims to be resting on: the choice row of a real `choose`
##      beat, and the kitchen's fridge shelf / worktop / prep board / placemat /
##      hand. Printed in centimetres, because "it looks fine" is not a clearance.
##
## `--resolution 2340x1080` is a REQUEST. The window manager clamps it to the
## display and files a 1.80 aspect as evidence for a 2.17 one, so a wide frame is
## rendered through an explicit `SubViewport` of exactly the asked-for size and
## **the written PNG's dimensions are read back off disk.** Same trick, same
## reason, as `shots_world.gd` and `shots_rc.gd`.

const OUT_DIR: String = "docs/shots/"

const Kit := preload("res://scripts/house/prop_kit.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const Items := preload("res://scripts/kitchen/kitchen_items.gd")
const Rules := preload("res://scripts/kitchen/kitchen_rules.gd")
const KitchenView := preload("res://scripts/kitchen/kitchen_view.gd")
const HouseLayout := preload("res://scripts/house/house_layout.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const ObjectSpawnerScript := preload("res://scripts/gameplay/object_spawner.gd")
const HouseStageScript := preload("res://scripts/gameplay/house_stage.gd")

## The mission whose second beat is a real `choose` -- no walk, four dressing
## objects laid out by `house_stage.gd`. That is the beat the RC checklist's open
## issue 5 is about.
const CHOOSE_MISSION: String = "morningRoutine"

## Half a centimetre of daylight under a prop is the most a four-year-old cannot
## see. Anything more is the brief's "floating in mid-air".
const FLOAT_TOLERANCE: float = 0.005

## How far the display row stands off the kitchen's back wall, and how high.
const ROW_Y: float = 1.00
const ROW_Z: float = 0.90
const ROW_PITCH: float = 0.34

var _suffix: String = "ipad"
var _frame: Vector2i = Vector2i.ZERO
var _viewport: SubViewport = null
var _world: Node = null
var _notes: Array = []
var _row_photographed: bool = false
## The `KitchenView` the item row is drawn by. Not in the scene: it is used only
## for its drawing methods.
var _view_node: Node3D = null
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_suffix = String(args[0]) if args.size() > 0 else "ipad"
	if args.size() > 1:
		var wide: PackedStringArray = String(args[1]).split("x")
		if wide.size() == 2:
			_frame = Vector2i(int(wide[0]), int(wide[1]))

	# `-- <suffix> [WxH] [only]` where `only` is `items`, `ground`, `kitchen` or
	# `choices`. Omitted, all four run; the choice sweep plays every shipped
	# mission and takes minutes, which is a long wait when the question is a
	# 9 cm apple.
	var only: String = String(args[2]) if args.size() > 2 else ""

	await process_frame
	if only.is_empty() or only == "items":
		await _shoot_items()
	if only.is_empty() or only == "ground":
		await _shoot_ground_proof()
	if only.is_empty() or only == "kitchen":
		await _audit_kitchen()
	if only.is_empty() or only == "choices":
		await _audit_choice_row()

	print("\n-- notes ------------------------------------------------------")
	for note: String in _notes:
		print("  %s" % note)
	if _fail.is_empty():
		print("\nPROPS SHOTS OK (%s)" % _suffix)
		quit(0)
	else:
		print("\nPROPS SHOTS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


# ---------------------------------------------------------------------------
# 1 + 2. The item row, in colour and in silhouette
# ---------------------------------------------------------------------------

func _shoot_items() -> void:
	await _open_world()
	_world.call("place_in_room", HouseLayout.KITCHEN, "default")
	await _settle(0.5)

	var room: Node = _world.call("get_room", HouseLayout.KITCHEN)
	if room == null:
		_fail.append("no kitchen to stand the props in")
		return
	# Aliz stands on the kitchen's default spawn, which is exactly where a
	# props close-up wants to be, and the HUD paints over the top of it. Both are
	# put aside for the two item shots and restored before anything that is about
	# the game rather than about the props.
	_set_chrome_visible(false)

	# The row is built by the SHIPPING drawing code. `_make_item` is what the
	# fridge, the worktop and her hand all call; a harness that drew its own
	# version of a bottle would prove nothing about the bottle in the game.
	_view_node = Node3D.new()
	_view_node.set_script(KitchenView)
	var stand := Node3D.new()
	stand.name = "PropDisplay"
	(room as Node3D).add_child(stand)
	stand.position = Vector3(0.0, ROW_Y, ROW_Z)

	# A harness camera, because the game's own three-quarter room shot is 4.3 m
	# back and this pass is about a 9 cm apple. Nothing else in the scene is
	# touched: same light, same walls, same material. Set up BEFORE either row, so
	# the two are photographed from exactly the same place.
	var camera := Camera3D.new()
	camera.name = "PropCamera"
	camera.fov = 30.0
	(room as Node3D).add_child(camera)
	camera.position = Vector3(0.0, ROW_Y + 1.72, ROW_Z + 3.35)
	camera.look_at(SpatialUtil.world_position(stand) + Vector3(0.0, 0.03, 0.0))
	camera.make_current()

	# The previous drawing, rebuilt (see `_legacy_item()`), then the shipping one.
	var before: int = await _lay_row(stand, camera, true)
	var after: int = await _lay_row(stand, camera, false)
	_notes.append("item set triangles: %d before, %d after (%+d)"
			% [before, after, after - before])

	stand.queue_free()
	camera.queue_free()
	_view_node.free()
	_view_node = null
	_set_chrome_visible(true)
	var world_camera: Node = _world.call("get_camera")
	if world_camera is Camera3D:
		(world_camera as Camera3D).make_current()
	await _settle(0.3)


## Lays every kitchen item out in one row, photographs it in colour and in
## silhouette, and returns the row's total triangle count.
##
## `legacy` swaps `_make_item()` for `_legacy_item()`, which is the drawing this
## pass replaced, rebuilt here. Reverting the real file to shoot a BEFORE is not
## available while other agents are editing the same tree, and a BEFORE taken at
## a different camera is not a comparison -- so both rows are built, lit and
## framed identically in one run, a few hundred milliseconds apart.
func _lay_row(stand: Node3D, camera: Camera3D, legacy: bool) -> int:
	var label: String = "BEFORE" if legacy else "AFTER"
	var ids: Array = Items.ids()
	var half: float = float(ids.size() - 1) * 0.5
	var total: int = 0
	var meshes: Array = []
	print("\n-- item meshes, %s ---------------------------------------" % label)
	print("  %-14s %6s  %-22s %s" % ["item", "tris", "extent WxHxD (cm)", "base offset"])
	for i: int in range(ids.size()):
		var item_id: String = String(ids[i])
		var node: MeshInstance3D = (
			_legacy_item(item_id) if legacy
			else _view_node.call("_make_item", item_id, Vector3.ZERO, 1.0)
		)
		if node == null or node.mesh == null:
			_fail.append("'%s' built no mesh (%s)" % [item_id, label])
			continue
		node.position = Vector3((float(i) - half) * ROW_PITCH, 0.0, 0.0)
		stand.add_child(node)
		meshes.append(node)
		var box: AABB = node.mesh.get_aabb()
		var tris: int = Kit.triangles(node.mesh)
		total += tris
		print("  %-14s %6d  %5.1f x %5.1f x %5.1f      %+.3f m" % [
			item_id, tris, box.size.x * 100.0, box.size.y * 100.0, box.size.z * 100.0,
			box.position.y])
		if not legacy and box.position.y < -0.02:
			_fail.append("'%s' is authored below its own origin (§6 pivot at base centre)"
					% item_id)
	print("  %-14s %6d  (the whole item set)" % ["TOTAL", total])

	var suffix: String = "_BEFORE" if legacy else ""
	camera.make_current()
	await _settle(0.35)
	await _shot("props_items%s" % suffix)

	# Silhouette: §2's "identifiable in pure black at 64 px", except in `ink`,
	# because §3 bans pure black even in a test render.
	var flat := StandardMaterial3D.new()
	flat.albedo_color = Palette.INK
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.roughness = 1.0
	for node: Variant in meshes:
		(node as MeshInstance3D).material_override = flat
	await _settle(0.2)
	await _shot("props_silhouette%s" % suffix)

	for node: Variant in meshes:
		stand.remove_child(node as Node)
		(node as Node).queue_free()
	await _settle(0.2)
	return total


## The item meshes exactly as `kitchen_view.gd::_make_item()` drew them before
## this pass: five generic silhouettes for eight items, so a banana and a spoon
## were one rounded lozenge, three bowls were one vessel, and two bottles were
## one cylinder. Kept here and nowhere else -- the game has one drawing.
func _legacy_item(item_id: String) -> MeshInstance3D:
	var size: float = Items.size_for(item_id)
	var color: Color = Items.color_for(item_id)
	var tool: SurfaceTool = Kit.begin()
	match Items.shape_for(item_id):
		"ball":
			Kit.box(tool, Kit.at(Vector3(0.0, size, 0.0)),
					Vector3(size * 2.0, size * 2.0, size * 2.0), color, size * 0.9, 3)
			Kit.cylinder(tool, Kit.at(Vector3(0.0, size * 2.1, 0.0)),
					size * 0.10, size * 0.42, Palette.deep(Palette.MINT), 6)
		"cup":
			Kit.cylinder(tool, Kit.at(Vector3(0.0, size * 0.85, 0.0)),
					size * 0.62, size * 1.7, color, 12)
			Kit.cylinder(tool, Kit.at(Vector3(0.0, size * 1.90, 0.0)),
					size * 0.34, size * 0.40, Palette.SOFT_PINK, 10)
			Kit.box(tool, Kit.at(Vector3(0.0, size * 2.24, 0.0)),
					Vector3(size * 0.44, size * 0.30, size * 0.44), Palette.SOFT_PINK,
					size * 0.14, 2)
		"bowl":
			Kit.vessel(tool, Kit.at(Vector3(0.0, size * 0.42, 0.0)),
					Kit.circle(size, 14), size * 0.84, size * 0.16, size * 0.16,
					Palette.CREAM, color)
		"flat":
			Kit.plate(tool, Kit.at(Vector3(0.0, size * 0.18, 0.0)),
					Kit.rounded_rect(Vector2(size * 1.9, size * 0.72), size * 0.34, 4),
					size * 0.34, color)
		_:
			Kit.box(tool, Kit.at(Vector3(0.0, size, 0.0)),
					Vector3(size * 1.6, size * 1.6, size * 1.6), color, size * 0.2, 2)

	var node := MeshInstance3D.new()
	node.name = "LegacyItem_%s" % item_id
	node.mesh = Kit.commit(tool)
	node.material_override = Kit.material()
	return node


# ---------------------------------------------------------------------------
# 1b. The two cosmetic fixes, A against B, in one run
# ---------------------------------------------------------------------------

## Photographs BOTH the old rule and the new one, at the same camera, in the same
## frame of the same room, one after the other.
##
## The honest alternative -- reverting the change, shooting, re-applying it --
## cannot be done while other agents are editing the same working tree, so the
## harness REBUILDS the previous behaviour instead:
##
##   * the pickups are real `ObjectSpawner` spawns of real `objects.json`
##     records, laid out with the real stage arithmetic (anchor at floor level,
##     `OBJECT_SCALE`, `SPAWN_LIFT`), and the BEFORE frame re-applies the exact
##     translation `model_transform()` used to use -- "centre the presented mesh
##     on `VISUAL_CENTRE_Y`" -- and nothing else;
##   * the beat marker is built twice: once from the code this pass replaced
##     (one `CylinderMesh`, `Color(0.66, 0.90, 0.81, 0.42)`, alpha, unshaded) and
##     once by the shipping `HouseStage`.
##
## So the two pictures differ by exactly the thing under review.
func _shoot_ground_proof() -> void:
	await _open_world()
	_world.call("place_in_room", HouseLayout.KITCHEN, "default")
	await _settle(0.5)
	var room: Node3D = _world.call("get_room", HouseLayout.KITCHEN) as Node3D
	if room == null:
		_fail.append("no kitchen to stand the pickups in")
		return
	_set_chrome_visible(false)

	var director: Node = _world.call("ensure_level_director")
	var library: Object = director.call("get_library") if director != null else null
	if library == null:
		_fail.append("no content library, so no real pickup can be spawned")
		return

	# The four worst cases from the BEFORE audit, plus the one that was BURIED --
	# a flat one, two long ones and a tall one, which is the whole span of the
	# fault.
	var anchor := Node3D.new()
	anchor.name = "GroundProof"
	room.add_child(anchor)
	anchor.position = Vector3(0.0, HouseLayout.FLOOR_Y, ROW_Z)
	anchor.scale = Vector3.ONE * HouseStageScript.OBJECT_SCALE

	var wanted: Array[String] = ["banana", "spoon", "circleToy", "milk"]
	var spawned: Array = []
	var half: float = float(wanted.size() - 1) * 0.5
	for i: int in range(wanted.size()):
		var record: Dictionary = library.call("get_object", wanted[i])
		if record.is_empty():
			_fail.append("no content record for '%s'" % wanted[i])
			continue
		var node: Area3D = ObjectSpawnerScript.spawn(record, "tap")
		if node == null:
			continue
		anchor.add_child(node)
		node.position = Vector3(
			(float(i) - half) * HouseStageScript.SPAWN_SPACING,
			HouseStageScript.SPAWN_LIFT, 0.0)
		spawned.append(node)

	# The beat marker goes on the floor just in front of the row, so one frame
	# carries both of this pass's cosmetic fixes.
	var stage: Node = director.call("get_stage")
	stage.call("show_beat_marker", SpatialUtil.world_position(anchor) + Vector3(0.0, 0.0, 0.75))
	print("\n-- ground proof ---------------------------------------------")
	var new_marker: MeshInstance3D = stage.get("_beat_marker") as MeshInstance3D
	var sample: MeshInstance3D = _legacy_beat_marker()
	var old_tris: int = Kit.triangles(sample.mesh)
	sample.free()
	print("  beat marker: field #%s alpha %.2f, %d triangles (was #a8e6cf alpha 0.42, %d)" % [
		Color(HouseStageScript.BEAT_MARKER_COLOR).to_html(true),
		float(Color(HouseStageScript.BEAT_MARKER_COLOR).a),
		Kit.triangles(new_marker.mesh) if new_marker != null else -1,
		old_tris])

	var camera := Camera3D.new()
	camera.name = "GroundCamera"
	camera.fov = 32.0
	room.add_child(camera)
	camera.position = Vector3(0.0, HouseLayout.FLOOR_Y + 1.62, ROW_Z + 3.30)
	camera.look_at(SpatialUtil.world_position(anchor) + Vector3(0.0, 0.16, 0.40))
	camera.make_current()
	await _settle(0.4)
	await _shot("props_ground")

	# Now the old rule, on the same objects, at the same camera.
	for node: Variant in spawned:
		var visual: MeshInstance3D = (node as Area3D).get_node_or_null("Visual") as MeshInstance3D
		if visual == null or visual.mesh == null:
			continue
		var oriented := Transform3D(visual.transform.basis, Vector3.ZERO)
		var presented: AABB = oriented * visual.mesh.get_aabb()
		oriented.origin = Vector3(
			0.0, ObjectSpawnerScript.VISUAL_CENTRE_Y, 0.0) - presented.get_center()
		visual.transform = oriented
	# And the old beat marker, built from the code that was replaced.
	stage.call("show_beat_marker", null)
	var old_marker: MeshInstance3D = _legacy_beat_marker()
	room.add_child(old_marker)
	SpatialUtil.set_world_position(old_marker,
			SpatialUtil.world_position(anchor) + Vector3(0.0, 0.008, 0.75))
	await _settle(0.4)
	await _shot("props_ground_BEFORE")

	old_marker.queue_free()
	for node: Variant in spawned:
		(node as Node).queue_free()
	anchor.queue_free()
	camera.queue_free()
	_set_chrome_visible(true)
	var world_camera: Node = _world.call("get_camera")
	if world_camera is Camera3D:
		(world_camera as Camera3D).make_current()
	await _settle(0.3)


## The beat marker exactly as `house_stage.gd` built it before this pass: one
## cylinder, mint at 42% alpha, unshaded. Kept here and nowhere else, so the
## comparison is honest and the game has only one marker.
func _legacy_beat_marker() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "LegacyBeatMarker"
	var mesh := CylinderMesh.new()
	mesh.top_radius = HouseStageScript.BEAT_MARKER_RADIUS
	mesh.bottom_radius = HouseStageScript.BEAT_MARKER_RADIUS
	mesh.height = HouseStageScript.BEAT_MARKER_HEIGHT
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.66, 0.90, 0.81, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 1.0
	node.material_override = material
	return node


## Hides (or restores) the character and every `CanvasLayer` in the world, so a
## close-up of a 9 cm apple is a picture of the apple.
func _set_chrome_visible(value: bool) -> void:
	var character: Node = _world.call("get_character")
	if character is Node3D:
		(character as Node3D).visible = value
	var layers: Array = []
	_collect_canvas_layers(_world, layers)
	for layer: Variant in layers:
		(layer as CanvasLayer).visible = value


func _collect_canvas_layers(node: Node, out: Array) -> void:
	if node is CanvasLayer:
		out.append(node)
	for child: Node in node.get_children():
		_collect_canvas_layers(child, out)


# ---------------------------------------------------------------------------
# 3a. The kitchen: does anything rest on thin air?
# ---------------------------------------------------------------------------

## Drives the real `KitchenState` through the verbs that put something down in
## each of the four places the kitchen has, and measures the bottom of the mesh
## that ends up there against the surface it is supposed to be on.
func _audit_kitchen() -> void:
	await _open_world()
	_world.call("place_in_room", HouseLayout.KITCHEN, "default")
	await _settle(0.5)
	var state: RefCounted = _world.call("get_kitchen_state")
	if state == null:
		_fail.append("the kitchen has no interactive state to audit")
		return

	print("\n-- kitchen float audit --------------------------------------")
	# As the child finds it: the bowl and the spoon live on the worktop.
	await _report_items("counter, as found", HouseLayout.WORKTOP_Y)

	state.call("set_open", Rules.STATION_FRIDGE, true)
	await _settle(0.6)
	await _report_items("fridge shelf", _fridge_shelf_y())
	await _shot("props_fridge")

	_apply(state.call("take", Rules.STATION_FRIDGE, "banana"), "take the banana")
	await _settle(0.4)
	await _report_items("carried in her hand", NAN)

	_apply(state.call("place", Rules.STATION_COUNTER), "put the banana on the board")
	await _settle(0.4)
	await _report_items("prep board", HouseLayout.WORKTOP_Y + HouseLayout.WORKTOP_BOARD_THICKNESS)
	await _shot("props_counter")

	_apply(state.call("take", Rules.STATION_COUNTER, "spoon"), "take the spoon")
	_apply(state.call("place", Rules.STATION_COUNTER), "mash it")
	_apply(state.call("take", Rules.STATION_COUNTER, "mashedBanana"), "pick the food up")
	_apply(state.call("place", Rules.STATION_TABLE), "serve it")
	await _settle(0.5)
	await _report_items("table placemat", _table_top() + HouseLayout.TABLE_MAT_THICKNESS)
	await _shot("props_served")

	# Put the kitchen back the way it was found, so a later shot is not looking at
	# this audit's leftovers.
	_apply(state.call("take", Rules.STATION_TABLE, "mashedBanana"), "clear the table")
	state.call("set_open", Rules.STATION_FRIDGE, false)
	await _settle(0.5)


## Every item mesh currently in the kitchen, measured against the NEAREST surface
## the kitchen actually provides. Attributing each item to a named surface rather
## than to one number per step is the only honest form of this test: the fridge
## keeps showing its contents while the banana is on the board, and a harness that
## compared everything on screen to the board's height would report the apple on
## the fridge shelf as floating 13 cm.
func _report_items(label: String, _surface_y: float) -> void:
	# The world auto-starts a level a few frames in, and a level start re-places
	# the child in the room its mission begins in. Walk back before measuring,
	# rather than measuring an empty kitchen the player is not standing in.
	if String(_world.call("get_current_room_id")) != HouseLayout.KITCHEN:
		_world.call("place_in_room", HouseLayout.KITCHEN, "default")
		await _settle(0.5)
	var found: Array = []
	_collect_items(_world, found)
	if found.is_empty():
		var hidden: Array = []
		_collect_items(_world, hidden, true)
		print("  %-22s (nothing visible; %d item mesh(es) built but hidden)"
				% [label, hidden.size()])
		return
	var surfaces: Dictionary = _kitchen_surfaces()
	for node: Variant in found:
		var mesh_node: MeshInstance3D = node
		var box: AABB = SpatialUtil.world_transform(mesh_node) * mesh_node.mesh.get_aabb()
		if _is_carried(mesh_node):
			print("  %-22s %-22s carried: bottom y=%+.3f  top y=%+.3f" % [
				label, mesh_node.name, box.position.y, box.position.y + box.size.y])
			continue
		var best: String = ""
		var best_gap: float = INF
		for surface_name: Variant in surfaces.keys():
			var gap: float = box.position.y - float(surfaces[surface_name])
			if absf(gap) < absf(best_gap):
				best_gap = gap
				best = String(surface_name)
		var verdict: String = "ok"
		if best_gap > FLOAT_TOLERANCE:
			verdict = "FLOATS %.1f cm" % (best_gap * 100.0)
			_fail.append("%s: %s floats %.1f cm above the %s"
					% [label, mesh_node.name, best_gap * 100.0, best])
		elif best_gap < -0.02:
			verdict = "SUNK %.1f cm" % (-best_gap * 100.0)
			_fail.append("%s: %s is %.1f cm inside the %s"
					% [label, mesh_node.name, -best_gap * 100.0, best])
		print("  %-22s %-22s bottom y=%+.3f  on the %-12s %s" % [
			label, mesh_node.name, box.position.y, best, verdict])


## The four heights the kitchen ever stands something on, read from the same
## constants `room.gd` draws them at.
func _kitchen_surfaces() -> Dictionary:
	var surfaces: Dictionary = {
		"worktop": HouseLayout.WORKTOP_Y,
		"prep board": HouseLayout.WORKTOP_Y + HouseLayout.WORKTOP_BOARD_THICKNESS,
	}
	var shelf: float = _fridge_shelf_y()
	if not is_nan(shelf):
		surfaces["fridge shelf"] = shelf
	var table: float = _table_top()
	if not is_nan(table):
		surfaces["placemat"] = table + HouseLayout.TABLE_MAT_THICKNESS
	return surfaces


func _is_carried(node: Node) -> bool:
	var walker: Node = node
	while walker != null:
		if String(walker.name) == "CarriedItem":
			return true
		walker = walker.get_parent()
	return false


## Godot renames a node whose name is already taken by a SIBLING to `@Name@42`,
## and `kitchen_view._refresh()` frees the old meshes with `queue_free()` -- which
## does not remove them from the parent until the end of the frame -- before
## adding the new ones. So the live `Item_bowl` is often called `@Item_bowl@37`,
## and a `begins_with()` filter silently reported an empty kitchen while the
## render plainly showed a bowl on the table. Matched by CONTAINS.
func _collect_items(node: Node, out: Array, include_hidden: bool = false) -> void:
	if node is MeshInstance3D and String(node.name).contains("Item_") \
			and not String(node.name).contains("LegacyItem_"):
		if (node as MeshInstance3D).mesh != null \
				and (include_hidden or node.is_visible_in_tree()):
			out.append(node)
	for child: Node in node.get_children():
		_collect_items(child, out, include_hidden)


func _fridge_shelf_y() -> float:
	var view := Node3D.new()
	view.set_script(KitchenView)
	var anchor: Dictionary = view.call("_anchor", Rules.STATION_FRIDGE)
	view.free()
	if anchor.is_empty():
		return NAN
	return (anchor["inside"] as Vector3).y


func _table_top() -> float:
	for row: Dictionary in HouseLayout.furniture(HouseLayout.KITCHEN):
		if String(row["targetId"]) == Rules.STATION_TABLE:
			return (row["position"] as Vector3).y + (row["size"] as Vector3).y * 0.5
	return NAN


# ---------------------------------------------------------------------------
# 3b. The choice row of a real `choose` beat
# ---------------------------------------------------------------------------

## Plays EVERY shipped mission and measures every choice row it lays out.
##
## Nothing here builds an object: the director, the stage, the mode handler and
## `ObjectSpawner` do it exactly as they do in the game. What is measured is the
## bottom of the visible mesh in world space, against the floor -- which is the
## only question a child asks of a thing lying in a room.
##
## Every mission rather than one, because a spawner defect is per-OBJECT: a
## garment cut-out is 26 cm tall and lands on the floor by luck, while a bar of
## soap and a shape-sorter plate are a few centimetres thick and hang in the air
## by most of `VISUAL_CENTRE_Y` times the row's scale. One beat would have proved
## the wrong thing.
func _audit_choice_row() -> void:
	await _open_world()
	var save: Node = root.get_node_or_null("SaveService")
	if save != null and save.has_method("reset_profile"):
		save.call("reset_profile")
	var director: Node = _world.call("ensure_level_director")
	if director == null:
		_fail.append("no level director, so no choose beat can be reached")
		return
	var library: Object = director.call("get_library")
	var mission_ids: PackedStringArray = PackedStringArray([CHOOSE_MISSION])
	if library != null and library.has_method("get_mission_ids"):
		mission_ids = library.call("get_mission_ids")

	print("\n-- choice row float audit ----------------------------------")
	var worst: float = 0.0
	var worst_what: String = ""
	var rows: int = 0
	for mission_id: String in mission_ids:
		var beats: Array = await _play_mission_rows(director, mission_id)
		for beat: Dictionary in beats:
			rows += 1
			print("  %-16s %-18s %-14s scale %.2f  against %s" % [
				mission_id, String(beat["taskId"]), String(beat["kind"]),
				float(beat["scale"]), String(beat["placeId"])])
			for line: Dictionary in (beat["objects"] as Array):
				var gap: float = float(line["gap"])
				var verdict: String = "ok"
				if gap > FLOAT_TOLERANCE:
					verdict = "FLOATS %.1f cm" % (gap * 100.0)
					_fail.append("%s/%s: %s floats %.1f cm above the floor"
							% [mission_id, String(beat["taskId"]), String(line["name"]),
								gap * 100.0])
				elif gap < -0.03:
					verdict = "SUNK %.1f cm" % (-gap * 100.0)
					_fail.append("%s/%s: %s is %.1f cm under the floor"
							% [mission_id, String(beat["taskId"]), String(line["name"]),
								-gap * 100.0])
				if gap > worst:
					worst = gap
					worst_what = "%s in %s/%s" % [
						String(line["name"]), mission_id, String(beat["taskId"])]
				print("      %-26s bottom y=%+.3f  top y=%+.3f  %s" % [
					String(line["name"]), float(line["bottom"]), float(line["top"]), verdict])
	_notes.append("%d choice rows measured; worst float %.1f cm (%s)"
			% [rows, worst * 100.0, worst_what if not worst_what.is_empty() else "none"])


## Starts `mission_id` for real, walks its beats the way arrival does, and returns
## one record per beat that actually laid objects out.
func _play_mission_rows(director: Node, mission_id: String) -> Array:
	var out: Array = []
	if not bool(director.call("_start_level", mission_id)):
		_fail.append("'%s' would not start" % mission_id)
		return out
	await _settle(0.5)
	var runner: Node = director.get("_runner")
	var stage: Node = director.call("get_stage")
	var seen: Array = []
	# A pickup is measured once. Forcing a beat to end from outside gameplay does
	# not always let the mode handler's `queue_free()` land before the next beat
	# spawns, so the same object can still be under the anchor two beats later --
	# a harness artefact, not a leak in the game, and this is what stops it being
	# reported as one.
	var measured: Dictionary = {}

	for _step: int in range(16):
		var plan: Dictionary = director.call("get_current_plan")
		var task_id: String = String(plan.get("taskId", ""))
		if task_id.is_empty() or seen.has(task_id):
			break
		seen.append(task_id)

		var destination: String = String(plan.get("destinationRoomId", ""))
		var walk_id: String = String(plan.get("walkTargetId", ""))
		if not destination.is_empty():
			var transition: Node = director.get("_transition")
			if transition != null and transition.has_method("request_transition"):
				transition.call("request_transition", destination,
						HouseLayout.arrival_spawn_id(String(plan.get("roomId", ""))))
		elif not walk_id.is_empty():
			director.call("_on_interaction_ready", walk_id)
		await _settle(0.7)

		if bool(plan.get("needsChoices", false)):
			var objects: Array = _measure_row(stage, measured)
			if not _row_photographed and String(plan.get("kind", "")) == "choose" \
					and not objects.is_empty():
				# Photographed HERE, while the beat is on screen. Taken after the
				# mission instead, it is a picture of the "Great job!" summary --
				# which is what the first run of this file filed as evidence.
				_row_photographed = true
				await _shot("props_choose")
			if not objects.is_empty():
				out.append({
					"taskId": task_id,
					"kind": String(plan.get("kind", "")),
					"placeId": String(stage.call("get_place_id")),
					"scale": float(stage.call("get_object_scale")),
					"objects": objects,
				})

		# Deliver the object so the beat ends and the next one is reached. The
		# runner's own entry point, the same call a dropped object makes.
		var object_id: String = String(plan.get("objectId", ""))
		if runner != null and runner.has_method("on_object_chosen") and not object_id.is_empty():
			runner.call("on_object_chosen", object_id)
		var deadline: int = Time.get_ticks_msec() + 3500
		while Time.get_ticks_msec() < deadline:
			await process_frame
			if runner != null and String(runner.call("get_current_task_id")) != task_id:
				break
		if runner != null and String(runner.call("get_current_task_id")) == task_id:
			# A care close-up or something else a headless walk cannot finish. Skip
			# it rather than pretend, and say so in the printout.
			if runner.has_method("skip_current_task"):
				runner.call("skip_current_task")
			await _settle(0.4)
	return out


## Bottom and top of every spawned pickup under the stage's anchor, in world
## space, with the gap to the floor.
func _measure_row(stage: Node, measured: Dictionary) -> Array:
	var anchor: Node3D = stage.call("get_object_anchor") as Node3D
	var out: Array = []
	if anchor == null:
		return out
	for child: Node in anchor.get_children():
		if not (child is Area3D):
			continue
		if measured.has(child.get_instance_id()):
			continue
		measured[child.get_instance_id()] = true
		var visual: MeshInstance3D = child.get_node_or_null("Visual") as MeshInstance3D
		if visual == null or visual.mesh == null:
			continue
		var box: AABB = SpatialUtil.world_transform(visual) * visual.mesh.get_aabb()
		var label: String = String(child.name)
		if child.get("object_id") != null and not String(child.get("object_id")).is_empty():
			label = String(child.get("object_id"))
		out.append({
			"name": label,
			"bottom": box.position.y,
			"top": box.position.y + box.size.y,
			"gap": box.position.y - HouseLayout.FLOOR_Y,
		})
	return out


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

func _open_world() -> void:
	if _world != null:
		return
	var packed: PackedScene = load("res://scenes/house/house_world.tscn")
	_world = packed.instantiate()
	# The world starts a session of its own on its first frame, which re-places
	# the child in whatever room that mission opens in -- in the middle of a
	# kitchen audit. Claimed as already booted, so this harness is the only thing
	# driving the house. The choice sweep asks for the director by name.
	_world.set("_director_booted", true)
	var host: Node = root
	if _frame != Vector2i.ZERO:
		_viewport = SubViewport.new()
		_viewport.size = _frame
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_viewport.transparent_bg = false
		root.add_child(_viewport)
		host = _viewport
	host.add_child(_world)
	await _settle(0.6)


func _apply(report: Variant, what: String) -> void:
	var dictionary: Dictionary = report if report is Dictionary else {}
	if not bool(dictionary.get("ok", false)):
		_fail.append("could not %s: %s" % [what, String(dictionary.get("say", ""))])


## Writes the PNG and READS ITS DIMENSIONS BACK. A shot whose size is not the
## size that was asked for is not evidence, it is a different composition.
func _shot(base_name: String) -> void:
	await RenderingServer.frame_post_draw
	var out_name: String = base_name + "_" + _suffix
	var source: Viewport = _viewport if _viewport != null else root.get_viewport()
	var image: Image = source.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + out_name + ".png")
	var err: int = image.save_png(path)
	if err != OK:
		_fail.append("could not write %s.png" % out_name)
		return
	var written: Image = Image.new()
	if written.load(path) != OK:
		_fail.append("%s.png will not re-open" % out_name)
		return
	var size: Vector2i = written.get_size()
	print("  shot %-32s %d x %d  (aspect %.2f)" % [
		out_name + ".png", size.x, size.y, float(size.x) / maxf(float(size.y), 1.0)])
	if _frame != Vector2i.ZERO and size != _frame:
		_fail.append("%s.png is %dx%d but %dx%d was asked for -- the window manager clamped it"
				% [out_name, size.x, size.y, _frame.x, _frame.y])


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
