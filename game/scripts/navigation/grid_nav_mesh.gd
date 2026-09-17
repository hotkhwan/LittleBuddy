extends RefCounted

## Builds a `NavigationMesh` from a declarative floor rectangle minus a list of
## obstacle rectangles, as a uniform grid of quads.
##
## ## Why not editor baking?
##
## `NavigationRegion3D.bake_navigation_mesh()` is the right answer for a real
## room full of modelled furniture, and `HouseWorld` should use it. It is the
## wrong answer for this spike, for three reasons:
##
##   1. Runtime baking parses source geometry off the GPU, which Godot itself
##      warns is a frame-blocking stall -- forbidden by the performance budget.
##   2. A mesh baked in the editor is an opaque binary blob in the .tscn. A
##      reviewer cannot see whether the closet is walled off, and neither can a
##      test.
##   3. Baking is not deterministic across Godot versions, so a test asserting
##      "this point is unreachable" would be asserting something about Recast.
##
## A grid of quads is deterministic, readable, diffable, costs nothing at load
## time, and -- because adjacent cells share exact vertex positions -- produces a
## correctly connected mesh with genuinely disconnected islands where the walls
## are. That makes "tap somewhere unreachable" a property the test suite can
## actually assert rather than hope for.
##
## Obstacles are inflated by `agent_radius` so the character's body, not its
## centre point, is what has to fit. The outer boundary is deliberately NOT
## inflated: a child tapping the skirting board should walk to the wall, not be
## refused.
##
## Pure and static: no Node, no SceneTree, no physics. Fully testable headlessly.

## Cells smaller than this are refused -- a 6 x 5 m floor at 1 cm cells is
## 300,000 polygons and would look like a hang rather than an error.
const MIN_CELL_SIZE: float = 0.05


## `bounds` and each entry of `obstacles` are `Rect2` in the XZ plane:
## `Rect2(min_x, min_z, size_x, size_z)`.
static func build(
	bounds: Rect2,
	cell_size: float,
	obstacles: Array,
	floor_y: float = 0.0,
	agent_radius: float = 0.15
) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.cell_size = maxf(cell_size * 0.5, 0.01)
	mesh.agent_radius = agent_radius
	if cell_size < MIN_CELL_SIZE or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return mesh

	var columns: int = int(floor(bounds.size.x / cell_size))
	var rows: int = int(floor(bounds.size.y / cell_size))
	if columns <= 0 or rows <= 0:
		return mesh

	# One shared vertex grid. Sharing exact vertex positions between neighbouring
	# quads is what makes the polygons connect into one walkable surface instead
	# of hundreds of isolated islands.
	var vertices := PackedVector3Array()
	vertices.resize((columns + 1) * (rows + 1))
	for row: int in range(rows + 1):
		for column: int in range(columns + 1):
			vertices[row * (columns + 1) + column] = Vector3(
				bounds.position.x + float(column) * cell_size,
				floor_y,
				bounds.position.y + float(row) * cell_size
			)
	mesh.vertices = vertices

	for row: int in range(rows):
		for column: int in range(columns):
			var centre := Vector2(
				bounds.position.x + (float(column) + 0.5) * cell_size,
				bounds.position.y + (float(row) + 0.5) * cell_size
			)
			if not is_walkable(centre, obstacles, agent_radius):
				continue
			var a: int = row * (columns + 1) + column
			var b: int = a + 1
			var c: int = b + columns + 1
			var d: int = a + columns + 1
			mesh.add_polygon(PackedInt32Array([a, b, c, d]))

	return mesh


## True when a character centred on `point` would not be standing in (or too
## close to) any obstacle.
static func is_walkable(point: Vector2, obstacles: Array, agent_radius: float) -> bool:
	for entry: Variant in obstacles:
		if not (entry is Rect2):
			continue
		if (entry as Rect2).grow(agent_radius).has_point(point):
			return false
	return true


## Convenience for placing a solid box mesh over an obstacle rectangle, so the
## thing the child can see and the thing the navigation mesh cuts out can never
## drift apart -- they are generated from the same numbers.
static func obstacle_centre(rect: Rect2, floor_y: float, height: float) -> Vector3:
	return Vector3(rect.position.x + rect.size.x * 0.5, floor_y + height * 0.5, rect.position.y + rect.size.y * 0.5)


static func obstacle_size(rect: Rect2, height: float) -> Vector3:
	return Vector3(rect.size.x, height, rect.size.y)
