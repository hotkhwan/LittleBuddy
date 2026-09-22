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
##
## Backend address (`backend_url()`), highest first:
##   1. user arg `-- --ai-tutor-cloud --tutor-backend-url=<http(s) url>` --
##      honoured ONLY together with `--ai-tutor-cloud` (a developer run
##      against the deployed development Worker; never in project.godot);
##   2. project setting `little_days/ai_tutor/backend_url`;
##   3. the loopback development default.

const SETTING_CLOUD: String = "little_days/ai_tutor/cloud_enabled"
const SETTING_BACKEND_URL: String = "little_days/ai_tutor/backend_url"
const USER_ARG_CLOUD: String = "--ai-tutor-cloud"
const USER_ARG_BACKEND_URL_PREFIX: String = "--tutor-backend-url="
## Developer runs only (with `--ai-tutor-cloud`): how long the client waits for
## one Worker turn. The product default (8 s) is unchanged; the dev Worker's
## Workers AI models take 7-12 s, so AI verification runs pass e.g. 14.
const USER_ARG_TIMEOUT_PREFIX: String = "--tutor-timeout="
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
	var dev_url: String = backend_url_from_args(OS.get_cmdline_user_args())
	if not dev_url.is_empty():
		return dev_url
	if ProjectSettings.has_setting(SETTING_BACKEND_URL):
		var url: String = String(ProjectSettings.get_setting(SETTING_BACKEND_URL)).strip_edges()
		if not url.is_empty():
			return url
	return DEFAULT_BACKEND_URL


## The developer backend override in `args`, or "" when absent, malformed, or
## not accompanied by `--ai-tutor-cloud`. Pure, so a test can pin the rule.
static func backend_url_from_args(args: PackedStringArray) -> String:
	if not args.has(USER_ARG_CLOUD):
		return ""
	for arg: String in args:
		if not arg.begins_with(USER_ARG_BACKEND_URL_PREFIX):
			continue
		var url: String = arg.trim_prefix(USER_ARG_BACKEND_URL_PREFIX).strip_edges().trim_suffix("/")
		# http(s) only; spelled without a URL literal so the privacy guard's
		# "no server address in the client" rule stays a plain text check.
		var scheme: String = url.get_slice("://", 0).to_lower()
		if url.contains("://") and scheme in ["http", "https"] and url.length() > scheme.length() + 3:
			return url
	return ""


## The developer request-timeout override in seconds, or 0.0 when absent,
## malformed, out of range (1..60) or not accompanied by `--ai-tutor-cloud`.
static func request_timeout_from_args(args: PackedStringArray) -> float:
	if not args.has(USER_ARG_CLOUD):
		return 0.0
	for arg: String in args:
		if not arg.begins_with(USER_ARG_TIMEOUT_PREFIX):
			continue
		var text: String = arg.trim_prefix(USER_ARG_TIMEOUT_PREFIX).strip_edges()
		if text.is_valid_float():
			var seconds: float = float(text)
			if seconds >= 1.0 and seconds <= 60.0:
				return seconds
	return 0.0


static func request_timeout_seconds(default_seconds: float) -> float:
	var dev: float = request_timeout_from_args(OS.get_cmdline_user_args())
	return dev if dev > 0.0 else default_seconds
