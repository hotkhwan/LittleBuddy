extends RefCounted

## Drop zones: no dead references.
##
## Every `interaction` value used anywhere in shipped content must map to a real
## zone id, and every activity scene must actually contain a node for every zone
## id. Also guards the lighting budget: an activity scene must never add a second
## camera, light or WorldEnvironment.

const DROP_ZONE_PATH: String = "res://scripts/gameplay/drop_zone.gd"
const LIBRARY_PATH: String = "res://scripts/content/content_library.gd"

const ACTIVITY_SCENES: Array[String] = [
	"res://scenes/activities/feeding.tscn",
	"res://scenes/activities/dressing.tscn",
	"res://scenes/activities/bath.tscn",
	"res://scenes/activities/play.tscn",
	"res://scenes/activities/bedtime.tscn",
]

## Types that belong to the nursery / baby room, never to an activity scene.
const FORBIDDEN_SCENE_TYPES: Array[String] = [
	"Camera3D", "DirectionalLight3D", "OmniLight3D", "SpotLight3D",
	"WorldEnvironment", "RigidBody3D", "GPUParticles3D", "CPUParticles3D",
]


func test_name() -> String:
	return "gameplay_drop_zones"


func run():
	var failures: Array = []
	var drop_zone: GDScript = load(DROP_ZONE_PATH) as GDScript
	if drop_zone == null:
		return ["could not load %s" % DROP_ZONE_PATH]

	failures.append_array(_test_mapping_is_total(drop_zone))
	failures.append_array(_test_content_interactions_resolve(drop_zone))
	failures.append_array(_test_scenes_contain_every_zone(drop_zone))
	failures.append_array(_test_scenes_add_no_camera_or_light())
	failures.append_array(_test_scenes_instantiate(drop_zone))
	return failures


## Text checks cannot catch a malformed .tscn, so actually instantiate each
## activity scene and confirm it exposes a usable context.
func _test_scenes_instantiate(drop_zone: GDScript):
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return failures  # Not running under the SceneTree runner; text checks stand.

	for scene_path: String in ACTIVITY_SCENES:
		var packed: Resource = load(scene_path)
		if packed == null or not (packed is PackedScene):
			failures.append("could not load %s as a PackedScene" % scene_path)
			continue
		var instance: Node = (packed as PackedScene).instantiate()
		if instance == null or not (instance is Node3D):
			failures.append("%s did not instantiate as a Node3D" % scene_path)
			continue

		tree.root.add_child(instance)

		if not instance.has_method("build_context"):
			failures.append("%s root is not an ActivityScene" % scene_path)
		else:
			var context: Dictionary = instance.call("build_context")
			var zones: Dictionary = context.get("dropZones", {})
			for zone_id: Variant in drop_zone.known_zone_ids():
				if not zones.has(String(zone_id)):
					failures.append("%s exposes no '%s' drop zone" % [scene_path, str(zone_id)])
			var points: Array = context.get("spawnPoints", [])
			if points.size() < 4:
				failures.append("%s exposes %d spawn points, expected at least 4"
						% [scene_path, points.size()])
			if context.get("objectAnchor", null) == null:
				failures.append("%s exposes no object anchor" % scene_path)

		tree.root.remove_child(instance)
		instance.free()
	return failures


func _test_mapping_is_total(drop_zone: GDScript):
	var failures: Array = []
	for interaction: Variant in drop_zone.known_interactions():
		var zone_id: String = drop_zone.zone_id_for_interaction(String(interaction))
		if zone_id.is_empty():
			failures.append("interaction '%s' maps to no zone id" % str(interaction))
		elif not bool(drop_zone.is_known_zone_id(zone_id)):
			failures.append("interaction '%s' maps to unknown zone '%s'" % [str(interaction), zone_id])
		elif String(drop_zone.node_name_for_zone_id(zone_id)).is_empty():
			failures.append("zone '%s' has no scene node name" % zone_id)

	if drop_zone.zone_id_for_interaction("somethingMadeUp") != "":
		failures.append("an unknown interaction should map to \"\", not to a real zone")
	return failures


## The important one: shipped content must never name an interaction we cannot
## stage. A dangling interaction would be an unfinishable task.
func _test_content_interactions_resolve(drop_zone: GDScript):
	var failures: Array = []
	var library_script: GDScript = load(LIBRARY_PATH) as GDScript
	if library_script == null:
		return ["could not load %s" % LIBRARY_PATH]
	var library: RefCounted = library_script.create()
	if library == null:
		return ["ContentLibrary.create() returned null"]

	var tasks: Array = library.get_tasks()
	if tasks.size() < 20:
		failures.append("expected the full task set, got %d" % tasks.size())

	var seen: Dictionary = {}
	for task: Variant in tasks:
		var task_dict: Dictionary = task
		var task_id: String = String(task_dict.get("taskId", ""))
		var interaction: String = String(task_dict.get("interaction", ""))
		seen[interaction] = true
		if not bool(drop_zone.is_known_interaction(interaction)):
			failures.append("task '%s' uses interaction '%s', which maps to no drop zone"
					% [task_id, interaction])

	# Also assert the content index's declared interaction vocabulary resolves,
	# so CONTENT adding a value there without a zone is caught immediately.
	for interaction: Variant in library.get_interactions():
		if not bool(drop_zone.is_known_interaction(String(interaction))):
			failures.append("content index declares interaction '%s' with no drop zone"
					% str(interaction))

	return failures


func _test_scenes_contain_every_zone(drop_zone: GDScript):
	var failures: Array = []
	for scene_path: String in ACTIVITY_SCENES:
		var text: String = _read_text(scene_path)
		if text.is_empty():
			failures.append("activity scene missing or empty: %s" % scene_path)
			continue
		if not ResourceLoader.exists(scene_path):
			failures.append("activity scene is not a loadable resource: %s" % scene_path)
		for zone_id: Variant in drop_zone.known_zone_ids():
			var node_name: String = drop_zone.node_name_for_zone_id(String(zone_id))
			if not text.contains('[node name="%s" type="Area3D"' % node_name):
				failures.append("%s has no %s node" % [scene_path, node_name])
			if not text.contains('zone_id = "%s"' % String(zone_id)):
				failures.append("%s declares no zone_id '%s'" % [scene_path, String(zone_id)])
		if not text.contains('[node name="ObjectAnchor" type="Node3D"'):
			failures.append("%s has no ObjectAnchor" % scene_path)
		if not text.contains('type="Marker3D"'):
			failures.append("%s has no spawn markers" % scene_path)
	return failures


## Lighting/camera budget: exactly one DirectionalLight3D and one Camera3D exist
## in the project, and neither belongs to an activity scene.
func _test_scenes_add_no_camera_or_light():
	var failures: Array = []
	for scene_path: String in ACTIVITY_SCENES:
		var text: String = _read_text(scene_path)
		if text.is_empty():
			continue
		for forbidden: String in FORBIDDEN_SCENE_TYPES:
			if text.contains('type="%s"' % forbidden):
				failures.append("%s must not contain a %s" % [scene_path, forbidden])
	return failures


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
