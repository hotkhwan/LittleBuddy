extends RefCounted
## Feature flags for Aliz Tutor Mode. Lead-owned.
##
## `AI_TUTOR_ENABLED` gates every path that could send a child's words or voice
## to a remote service. It is OFF in every public build until the privacy and
## compliance review (docs/ALIZ_TUTOR_PRIVACY_REVIEW.md) passes and the backend
## is configured. The LOCAL scripted tutor (deterministic lesson engine, bundled
## voice or on-device TTS, no network) is always allowed; that is what ships
## while the flag is off.
##
## Resolution order, highest first:
##   1. project setting `little_days/ai_tutor/cloud_enabled` (bool; the value
##      baked into an export -- keep it false for public builds);
##   2. user arg `-- --ai-tutor-cloud` for a developer run against a local
##      backend (never reaches an exported build's settings);
##   3. default false.
## Nothing in the game may bypass `cloud_enabled()`; tests assert the export
## presets and project.godot keep it false.

const SETTING_CLOUD: String = "little_days/ai_tutor/cloud_enabled"
const SETTING_BACKEND_URL: String = "little_days/ai_tutor/backend_url"
const USER_ARG_CLOUD: String = "--ai-tutor-cloud"
const DEFAULT_BACKEND_URL: String = "http://127.0.0.1:8787"


static func cloud_enabled() -> bool:
	if ProjectSettings.has_setting(SETTING_CLOUD) and bool(ProjectSettings.get_setting(SETTING_CLOUD)):
		return true
	return OS.get_cmdline_user_args().has(USER_ARG_CLOUD)


## The local scripted tutor is always available: offline, deterministic, no
## child data leaves the device.
static func local_tutor_enabled() -> bool:
	return true


static func backend_url() -> String:
	if ProjectSettings.has_setting(SETTING_BACKEND_URL):
		var url: String = String(ProjectSettings.get_setting(SETTING_BACKEND_URL)).strip_edges()
		if not url.is_empty():
			return url
	return DEFAULT_BACKEND_URL
