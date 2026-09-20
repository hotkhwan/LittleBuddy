extends RefCounted
## The cloud half of Aliz Tutor Mode stays OFF in every build until the privacy
## review passes. This case reads the committed files, not the running
## settings, so a developer's local override can never make it green.

const FLAGS: String = "res://scripts/tutor/tutor_flags.gd"
const PROJECT: String = "res://project.godot"
const PRESETS: String = "res://export_presets.cfg"


func test_name() -> String:
	return "tutor_flags"


func run():
	var failures: Array = []
	var script: GDScript = load(FLAGS)
	if script == null:
		return ["cannot load %s" % FLAGS]

	var project_text: String = _read(PROJECT)
	if not project_text.contains("ai_tutor/cloud_enabled=false"):
		failures.append("project.godot must commit little_days/ai_tutor/cloud_enabled=false")
	if project_text.contains("ai_tutor/cloud_enabled=true"):
		failures.append("project.godot enables the cloud tutor; it must stay off until the privacy review passes")

	var presets_text: String = _read(PRESETS)
	for key: String in ["ai_tutor/cloud_enabled=true", "--ai-tutor-cloud"]:
		if presets_text.contains(key):
			failures.append("export_presets.cfg carries '%s'; an export must never arm the cloud tutor" % key)
	if presets_text.contains("OPENAI") or project_text.contains("OPENAI"):
		failures.append("a provider key name appears in committed project files")

	if bool(script.cloud_enabled()) and not OS.get_cmdline_user_args().has(script.USER_ARG_CLOUD):
		failures.append("TutorFlags.cloud_enabled() is true with no developer user arg")
	if not bool(script.local_tutor_enabled()):
		failures.append("the local scripted tutor must always be enabled")
	if String(script.backend_url()).is_empty():
		failures.append("backend_url() must fall back to the local development default")
	return failures


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""
