extends RefCounted

const Kitchen := preload("res://scripts/kitchen/kitchen_view.gd")
const Registry := preload("res://scripts/house/prop_registry.gd")

func test_name() -> String:
	return "bottle_presentation"

func run():
	var failures: Array = []
	var factory := Kitchen.new()
	var empty: MeshInstance3D = factory.call("_make_item", "bottle", Vector3.ZERO)
	var milk: MeshInstance3D = factory.call("_make_item", "bottleOfMilk", Vector3.ZERO)
	var empty_again: MeshInstance3D = factory.call("_make_item", "bottle", Vector3.ZERO)
	if not Registry.available("babyBottle"):
		failures.append("accepted bottle must be available in the runtime registry")
	if milk.mesh.get_surface_count() != empty.mesh.get_surface_count() + 1:
		failures.append("prepared milk needs a visible fill surface")
	if empty_again.mesh.get_surface_count() != empty.mesh.get_surface_count():
		failures.append("preparing milk must not mutate the shared empty mesh")
	for model: MeshInstance3D in [empty, milk, empty_again]:
		if absf(model.mesh.get_aabb().position.y) > 0.002:
			failures.append("bottle must remain base-anchored for carry and counter placement")
		model.free()
	factory.free()
	return failures
