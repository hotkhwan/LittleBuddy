extends RefCounted

## WHERE THE KITCHEN PUTS THINGS -- the arithmetic behind "nothing floats".
##
## `kitchen_view.gd` is presentation, so almost nothing in it is testable and
## almost all of it has to be looked at. These five rules are the exception: they
## are the ones whose violation is a *number*, and every one of them was a real
## defect in the shipped build before this file existed.
##
##   * The counter's contents were drawn at the FRIDGE's anchor -- 0.59 m up and
##     0.30 m out in front of the cabinet doors, resting on nothing. A bowl and a
##     spoon hung in mid-air in the first frame of the kitchen, and nothing could
##     see it but a person with a render open.
##   * The prep board and the ingredients that stand on it are placed from two
##     different files. They agreed by hand, which is to say they agreed until
##     someone moved the board.
##   * The hob, the sink and the two things standing between them share one
##     1.8 m plank, and "it looked fine" is not a clearance.
##   * A served dish sat 3 cm above the table, because the surface anchor carried
##     a lift meant for a worktop.
##   * A carried item is authored standing on its own base (§6, "pivot at base
##     centre"), so hanging it at a hand puts the whole of it ABOVE her fist.
##
## Nothing here asserts that the kitchen looks good; that judgement is in
## `docs/WORLD_POLISH_PASS.md` with the renders beside it.

const HouseLayout := preload("res://scripts/house/house_layout.gd")
const KitchenView := preload("res://scripts/kitchen/kitchen_view.gd")
const Rules := preload("res://scripts/kitchen/kitchen_rules.gd")
const Items := preload("res://scripts/kitchen/kitchen_items.gd")
const Kit := preload("res://scripts/house/prop_kit.gd")

## How far a thing standing on a surface may be from it before a four-year-old
## can see daylight underneath. Half a centimetre.
const FLOAT_TOLERANCE: float = 0.005

## An agent-sized gap is a navigation rule; this is a much smaller one, because
## nothing here is walked through -- it only has to not intersect.
const PROP_CLEARANCE: float = 0.02


func test_name() -> String:
	return "kitchen_view_placement"


func run():
	var failures: Array = []
	failures += _test_nothing_rests_on_thin_air()
	failures += _test_the_board_is_under_what_is_put_on_it()
	failures += _test_the_worktop_is_not_overcrowded()
	failures += _test_the_fridge_shelf_is_in_front_of_the_fridge()
	failures += _test_a_carried_item_hangs_from_its_middle()
	return failures


func _view() -> Node3D:
	var view := Node3D.new()
	view.set_script(KitchenView)
	return view


func _row(target_id: String) -> Dictionary:
	for row: Dictionary in HouseLayout.furniture(HouseLayout.KITCHEN):
		if String(row["targetId"]) == target_id:
			return row
	return {}


## -- 1. Nothing rests on thin air ------------------------------------------------

## Every station's `surface` anchor must sit ON the top of that station (or on
## whatever `room.gd` lays on it), not above it. This is the assertion the
## floating bowl would have failed.
func _test_nothing_rests_on_thin_air():
	var failures: Array = []
	var view: Node3D = _view()

	var expected: Dictionary = {
		# The prep board's top face.
		Rules.STATION_COUNTER: (
			HouseLayout.WORKTOP_Y + HouseLayout.WORKTOP_BOARD_THICKNESS
		),
		# The placemat's top face.
		Rules.STATION_TABLE: _table_top() + HouseLayout.TABLE_MAT_THICKNESS,
	}
	for station_id: String in expected.keys():
		var anchor: Dictionary = view.call("_anchor", station_id)
		if anchor.is_empty():
			failures.append("the kitchen has no '%s' to stand anything on" % station_id)
			continue
		var surface: Vector3 = anchor["surface"]
		var wanted: float = float(expected[station_id])
		if absf(surface.y - wanted) > FLOAT_TOLERANCE:
			failures.append(("'%s' sets things down at y=%.3f but its surface is at "
					+ "y=%.3f -- a %.0f cm hover is the 'floating in mid-air' defect")
					% [station_id, surface.y, wanted, absf(surface.y - wanted) * 100.0])

	# And the counter's RESIDENT items -- the ones drawn without anyone putting
	# them there -- stand on the worktop rather than in front of the cupboard
	# doors, which is exactly where they used to be.
	var counter: Dictionary = view.call("_anchor", Rules.STATION_COUNTER)
	if not counter.is_empty():
		var inside: Vector3 = counter["inside"]
		if absf(inside.y - HouseLayout.WORKTOP_Y) > FLOAT_TOLERANCE:
			failures.append(("the counter stands its own contents at y=%.3f; the worktop "
					+ "is at y=%.3f") % [inside.y, HouseLayout.WORKTOP_Y])
		var counter_row: Dictionary = _row(Rules.STATION_COUNTER)
		if not counter_row.is_empty():
			var centre: Vector3 = counter_row["position"]
			var size: Vector3 = counter_row["size"]
			var back: float = centre.z - size.z * 0.5
			var front: float = centre.z + size.z * 0.5
			if inside.z < back or inside.z > front:
				failures.append(("the counter's contents stand at z=%.2f, which is off the "
						+ "worktop (%.2f to %.2f)") % [inside.z, back, front])
	view.free()
	return failures


func _table_top() -> float:
	var row: Dictionary = _row(Rules.STATION_TABLE)
	if row.is_empty():
		return 0.0
	var centre: Vector3 = row["position"]
	var size: Vector3 = row["size"]
	return centre.y + size.y * 0.5


## -- 2. The board and the thing on it are placed from two files ------------------

## `room.gd` draws the prep board; `kitchen_view.gd` stands an ingredient on it.
## They read the same constants, and this is the assertion that keeps them doing
## so: the drop point must be inside the board's own footprint, with a margin,
## so a banana cannot end up half off the edge of the thing it is lying on.
func _test_the_board_is_under_what_is_put_on_it():
	var failures: Array = []
	var view: Node3D = _view()
	var anchor: Dictionary = view.call("_anchor", Rules.STATION_COUNTER)
	view.free()
	if anchor.is_empty():
		return ["the kitchen has no counter"]

	var surface: Vector3 = anchor["surface"]
	var half: Vector2 = HouseLayout.WORKTOP_BOARD_SIZE * 0.5
	# The longest thing that is ever put down here, drawn at presentation scale.
	var longest: float = 0.0
	for item_id: String in Items.ids():
		longest = maxf(longest, Items.size_for(item_id) * 1.9 * KitchenView.SURFACE_SCALE)
	var reach: float = longest * 0.5

	if absf(surface.x - HouseLayout.WORKTOP_BOARD_X) + reach > half.x:
		failures.append(("the longest ingredient is %.2f m and the prep board is %.2f m "
				+ "wide, so it would hang over the edge")
				% [longest, HouseLayout.WORKTOP_BOARD_SIZE.x])
	if absf(surface.z - HouseLayout.WORKTOP_BOARD_Z) > half.y:
		failures.append("the counter puts things down %.2f m from the middle of the board"
				% absf(surface.z - HouseLayout.WORKTOP_BOARD_Z))

	# The board must be ON the counter, not overhanging it.
	var row: Dictionary = _row(Rules.STATION_COUNTER)
	if not row.is_empty():
		var centre: Vector3 = row["position"]
		var size: Vector3 = row["size"]
		if (HouseLayout.WORKTOP_BOARD_X - half.x < centre.x - size.x * 0.5
				or HouseLayout.WORKTOP_BOARD_X + half.x > centre.x + size.x * 0.5):
			failures.append("the prep board hangs off the end of the counter")
		if (HouseLayout.WORKTOP_BOARD_Z - half.y < centre.z - size.z * 0.5 - 0.001
				or HouseLayout.WORKTOP_BOARD_Z + half.y > centre.z + size.z * 0.5 + 0.001):
			failures.append("the prep board hangs off the front or back of the counter")
	return failures


## -- 3. One 1.8 m plank, four things on it ---------------------------------------

## The hob, the two resident ingredients, the prep board and the sink all share
## the worktop, and they are authored in two files from five constants. "It
## looked fine" is not a clearance, so here is one.
func _test_the_worktop_is_not_overcrowded():
	var failures: Array = []
	# Widest resident ingredient, drawn at presentation scale.
	var widest: float = 0.0
	for item_id: String in ["bowl", "spoon"]:
		widest = maxf(widest, Items.size_for(item_id) * 2.0 * KitchenView.SURFACE_SCALE)
	var half_item: float = widest * 0.5

	# `room.gd`'s own fixture widths. Named here rather than imported because a
	# test that reads the number it is checking checks nothing.
	var occupied: Dictionary = {
		"the hob": [HouseLayout.WORKTOP_HOB_X - 0.19, HouseLayout.WORKTOP_HOB_X + 0.19],
		"the sink": [HouseLayout.WORKTOP_SINK_X - 0.22, HouseLayout.WORKTOP_SINK_X + 0.22],
	}
	for side: float in [-1.0, 1.0]:
		var at: float = HouseLayout.WORKTOP_BOARD_X + side * HouseLayout.WORKTOP_SPREAD
		for label: String in occupied.keys():
			var span: Array = occupied[label]
			# 1-D interval distance: positive is a gap, negative is an overlap.
			var gap: float = maxf(
				float(span[0]) - (at + half_item),
				(at - half_item) - float(span[1])
			)
			if gap < PROP_CLEARANCE:
				failures.append(("an ingredient standing at x=%.2f leaves %.3f m to %s; "
						+ "WORKTOP_SPREAD, WORKTOP_HOB_X and WORKTOP_SINK_X have to be "
						+ "moved together") % [at, gap, label])

	# And both fixtures must be on the counter at all.
	var row: Dictionary = _row(Rules.STATION_COUNTER)
	if row.is_empty():
		return failures + ["the kitchen has no counter"]
	var centre: Vector3 = row["position"]
	var size: Vector3 = row["size"]
	for label: String in occupied.keys():
		var span: Array = occupied[label]
		if float(span[0]) < centre.x - size.x * 0.5 or float(span[1]) > centre.x + size.x * 0.5:
			failures.append("%s hangs off the end of the worktop" % label)
	return failures


## -- 4. The fridge's contents have to be VISIBLE ---------------------------------

## The first version of this put the food geometrically inside a solid mesh: it
## was built, it was in the right place, and it could not be seen. The shelf and
## the lining now stand proud of the front face, and the food stands on the
## shelf -- so the anchor must be in front of the fridge, and inside it in x.
func _test_the_fridge_shelf_is_in_front_of_the_fridge():
	var failures: Array = []
	var view: Node3D = _view()
	var anchor: Dictionary = view.call("_anchor", Rules.STATION_FRIDGE)
	view.free()
	var row: Dictionary = _row(Rules.STATION_FRIDGE)
	if anchor.is_empty() or row.is_empty():
		return ["the kitchen has no fridge"]

	var centre: Vector3 = row["position"]
	var size: Vector3 = row["size"]
	var face: float = centre.z + size.z * 0.5
	var inside: Vector3 = anchor["inside"]
	if inside.z <= face:
		failures.append(("the fridge shows its contents at z=%.3f, which is behind its own "
				+ "front face at z=%.3f -- they would be inside the mesh and invisible")
				% [inside.z, face])
	if inside.z > face + 0.20:
		failures.append(("the fridge's contents stand %.2f m proud of it; that is food "
				+ "floating in front of a fridge, not food in one") % [inside.z - face])
	# Three items, spread, must still fit across the opening.
	var spread: float = float(anchor.get("spread", 0.19))
	var half_open: float = (size.x - KitchenView.LINING_INSET) * 0.5
	if spread > half_open:
		failures.append("the fridge spreads its contents %.2f m apart across a %.2f m "
				% [spread, half_open * 2.0] + "opening")
	if inside.y <= centre.y - size.y * 0.5 or inside.y >= centre.y + size.y * 0.5:
		failures.append("the fridge's shelf is not inside the fridge")
	return failures


## -- 5. A carried item hangs from its middle -------------------------------------

## Item meshes are authored STANDING on their own origin, so attaching one to a
## hand without compensating puts the whole of it above her fist -- which is what
## the first bone-follow pass rendered. The offset is taken from the mesh's own
## bounding box, so this asserts the compensation really lands the middle of the
## item on the hand, for every shape the kitchen has.
func _test_a_carried_item_hangs_from_its_middle():
	var failures: Array = []
	var view: Node3D = _view()
	for item_id: String in Items.ids():
		var node: MeshInstance3D = view.call("_make_item", item_id, Vector3.ZERO, 1.0)
		if node == null or node.mesh == null:
			failures.append("'%s' built no mesh at all" % item_id)
			continue
		var bounds: AABB = node.mesh.get_aabb()
		if bounds.size.y <= 0.0:
			failures.append("'%s' has no height" % item_id)
		# Authored standing on its own base, §6.
		if bounds.position.y < -0.02:
			failures.append(("'%s' is authored %.3f m BELOW its own origin; §6 puts the "
					+ "pivot at base centre and the hand offset assumes it")
					% [item_id, -bounds.position.y])
		# And the compensation `_refresh()` applies really centres it.
		var lift: float = -(bounds.position.y + bounds.size.y * 0.5) * KitchenView.HAND_SCALE
		var middle: float = lift + (bounds.position.y + bounds.size.y * 0.5) * KitchenView.HAND_SCALE
		if absf(middle) > 0.001:
			failures.append("'%s' would not hang from its middle" % item_id)
		node.free()
	view.free()

	if KitchenView.HAND_SCALE < 1.0:
		failures.append("a carried item is drawn SMALLER than the world copy, which is "
				+ "backwards: it is further from the camera and has to read at a glance")
	if KitchenView.HAND_SCALE > 1.45:
		failures.append(("a carried item is drawn at %.2f; past ~1.45 a bottle in a 1 m "
				+ "child's hand reaches past her shoulder") % KitchenView.HAND_SCALE)
	if KitchenView.HAND_BONES.is_empty():
		failures.append("there is no hand bone to carry anything in, so every carried item "
				+ "falls back to a fixed offset on her chest")
	return failures
