extends Node
class_name RewardManager

## Bridges completed activities to persisted stars via SaveService.
## Accesses the SaveService autoload defensively so this scene keeps working
## in isolation (e.g. scene previews, tests) even if SaveService is missing.

signal star_awarded(total: int)


## Awards `stars` for `activity_id`, persists progress, and returns the new
## star total (0 if SaveService is unavailable).
func award(activity_id: String, stars: int = 1) -> int:
	var save_service: Node = get_node_or_null("/root/SaveService")
	var total: int = 0

	if save_service != null and save_service.has_method("add_stars"):
		total = int(save_service.add_stars(stars))
	if save_service != null and save_service.has_method("mark_activity_completed"):
		save_service.mark_activity_completed(activity_id)

	star_awarded.emit(total)
	return total


## Convenience read of the current star total; returns 0 if unavailable.
func get_stars() -> int:
	var save_service: Node = get_node_or_null("/root/SaveService")
	if save_service != null and save_service.has_method("get_stars"):
		return int(save_service.get_stars())
	return 0
