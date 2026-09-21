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
	if project_text.contains("workers.dev") or project_text.contains("--tutor-backend-url"):
		failures.append("project.godot must not carry a development backend address; the dev Worker is a user arg only")

	var presets_text: String = _read(PRESETS)
	for key: String in ["ai_tutor/cloud_enabled=true", "--ai-tutor-cloud", "--tutor-backend-url"]:
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

	# `--tutor-backend-url=` is honoured only together with `--ai-tutor-cloud`,
	# only for http(s), and never from the project settings.
	var dev: String = "https://tutor.example"
	if String(script.backend_url_from_args(PackedStringArray(["--tutor-backend-url=%s" % dev]))) != "":
		failures.append("--tutor-backend-url without --ai-tutor-cloud must be ignored")
	if String(script.backend_url_from_args(PackedStringArray(["--ai-tutor-cloud", "--tutor-backend-url=%s/" % dev]))) != dev:
		failures.append("--tutor-backend-url with --ai-tutor-cloud must be honoured (trailing slash trimmed)")
	if String(script.backend_url_from_args(PackedStringArray(["--ai-tutor-cloud", "--tutor-backend-url=ftp://x"]))) != "":
		failures.append("--tutor-backend-url must accept http(s) only")
	if String(script.backend_url_from_args(PackedStringArray(["--ai-tutor-cloud"]))) != "":
		failures.append("--ai-tutor-cloud alone leaves backend_url() to the settings/default")
	if not OS.get_cmdline_user_args().has(script.USER_ARG_CLOUD) and String(script.backend_url()) != _configured_default(script):
		failures.append("without the developer args backend_url() must be the setting or the loopback default, got %s" % String(script.backend_url()))
	return failures


static func _configured_default(script: GDScript) -> String:
	if ProjectSettings.has_setting(script.SETTING_BACKEND_URL):
		var url: String = String(ProjectSettings.get_setting(script.SETTING_BACKEND_URL)).strip_edges()
		if not url.is_empty():
			return url
	return String(script.DEFAULT_BACKEND_URL)


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""
