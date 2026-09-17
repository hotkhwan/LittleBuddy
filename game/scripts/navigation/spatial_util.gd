extends RefCounted

## One small utility: a world position that also works for a node which is not
## (yet) inside the scene tree.
##
## `Node3D.global_position` asserts `is_inside_tree()` and otherwise logs an
## error and returns the identity transform's origin -- silently (0, 0, 0). That
## turns an unparented target into "the middle of the room" rather than into a
## loud failure, and it makes the whole activity-target layer untestable in the
## headless `--script` runner, where nodes are built and queried without ever
## being added to a running tree.
##
## Accumulating the parent transforms by hand costs a handful of matrix
## multiplies on a chain that is two or three deep, and removes an entire class
## of "why is everything at the origin" bugs.


static func world_position(node: Node3D) -> Vector3:
	return world_transform(node).origin


## Places `node` at a world position, whether or not it is inside the tree. Out
## of the tree it converts into the parent's space by hand, so a scene built and
## exercised headlessly ends up with exactly the same layout as a running one.
static func set_world_position(node: Node3D, world: Vector3) -> void:
	if node == null:
		return
	if node.is_inside_tree():
		node.global_position = world
		return
	var parent: Node = node.get_parent()
	if parent is Node3D:
		node.position = world_transform(parent as Node3D).affine_inverse() * world
	else:
		node.position = world


static func world_transform(node: Node3D) -> Transform3D:
	if node == null:
		return Transform3D.IDENTITY
	if node.is_inside_tree():
		return node.global_transform
	var result: Transform3D = node.transform
	var parent: Node = node.get_parent()
	var guard: int = 0
	while parent is Node3D and guard < 64:
		guard += 1
		result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result
