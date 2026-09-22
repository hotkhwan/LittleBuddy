extends RefCounted

## PRIVACY GUARDS FOR ALIZ TUTOR MODE.
##
## The gate document `docs/ALIZ_TUTOR_PRIVACY_REVIEW.md` says the cloud tutor is
## OFF and that, while it is off, nothing under `game/` can reach a network, a
## provider, or the microphone outside the on-device speech stack. This case is
## what makes those sentences true tomorrow as well as today. It reads SOURCE,
## never the running settings, so a developer override can never make it green.
##
## What it asserts:
##
##   1. No script or scene under `res://scripts`, `res://scenes`, `res://addons`
##      names a provider (OpenAI, Anthropic, Gemini, Meshy), a key environment
##      variable, a `sk-...` shaped literal, an `Authorization`/`Bearer` header
##      or a provider hostname. Anything that talks to the backend gets its
##      address from `TutorFlags.backend_url()` and nowhere else; the only URL
##      literals allowed in the game are the loopback development default in
##      `tutor_flags.gd`, the Parent Corner text link (already gated by
##      `test_entitlement_no_purchase_guard.gd`) and the URL *markers* the turn
##      validator rejects on.
##   2. Nothing opens the microphone outside `res://scripts/speech`. Godot's own
##      capture primitives (`AudioStreamMicrophone`, `AudioEffectRecord`,
##      `audio/driver/enable_input`) appear nowhere at all: recognition is the
##      frozen on-device iOS plugin, reached only through `SpeechService`, and
##      only `ios_speech_backend.gd` may touch that native singleton.
##   3. `OS.shell_open` (and the other process launchers) are reachable from no
##      child-facing file. Today the count is ZERO. If a future grown-up feature
##      needs one, it may live only under `res://scenes/parent/` in a file that
##      also instantiates the `ParentalGate`.
##   4. Network primitives (`HTTPRequest`, `HTTPClient`, sockets) are limited to
##      an ALLOWLIST of tutor files (below). Every allowlisted file, once it
##      exists, must call `TutorFlags.cloud_enabled()` BEFORE its first network
##      primitive in source order, must take its address from `backend_url()`,
##      and must contain no URL literal of its own. A file on the allowlist that
##      does not exist yet is simply skipped, so the list can be written ahead
##      of the code.
##   5. Export presets and project.godot carry no `--ai-tutor-cloud`, no
##      `cloud_enabled=true`, no key names, no `INTERNET` or `RECORD_AUDIO`
##      Android permission.
##   6. `backend/.env.example` (when the backend has landed in this checkout)
##      holds names only, and `.gitignore` covers `.env`, `backend/.env` and
##      `backend/data/`.
##
## The git-history secret scan (item vii of the review) needs `git` and is run
## from the shell; its commands and result are recorded in the review document.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

# -- allowlists (the ONLY lines Agents E and F should need to touch) ---------

## Files that may construct a network primitive. Each entry must be a script
## under `res://scripts/tutor/`. To add one: append its `res://` path with a
## one-line comment naming the owner and the reason, and make sure the file
## reads `TutorFlags.cloud_enabled()` before its first `HTTPRequest`/`HTTPClient`
## IN SOURCE ORDER (so construct the node lazily inside the guarded branch, not
## in a member initialiser) and builds its address from `TutorFlags.backend_url()`.
const NETWORK_ALLOWLIST: Array[String] = [
	# Agent F -- server-authoritative quota/entitlement client (cloud only):
	"res://scripts/tutor/quota/cloud_quota_client.gd",
	# Agent E -- cloud conversation provider (POST turns to the backend):
	"res://scripts/tutor/providers/backend_conversation_provider.gd",
	# Agent E -- cloud synthesis provider (backend TTS bytes, flag-gated):
	"res://scripts/tutor/providers/backend_synthesis_provider.gd",
	# Agent E -- realtime voice transport (WebSocket to the URL the backend's
	# token endpoint hands out; ephemeral secret; flag-gated):
	"res://scripts/tutor/voice/transports/cloud_realtime_transport.gd",
	# Agent E -- cloud tutor REST client (sessions, realtime token, turns, end,
	# quota against the Worker contract; parent token + approval headers;
	# flag-gated; loopback-only test override):
	"res://scripts/tutor/cloud/cloud_tutor_api.gd",
]

## First-party identity is independent of the child tutor upload switch: guest
## creation/linking is parent/account infrastructure and sends no child voice.
## It must still have no committed host literal; project.godot keeps its URL empty.
const IDENTITY_NETWORK_ALLOWLIST: Array[String] = [
	"res://scripts/account/identity_api.gd",
]

## Provider-neutral realtime voice transport. It accepts only a server-issued
## WSS URL and refuses to connect unless adult/synthetic QA is active or both
## the remote child-audio switch and current parent consent are true.
const VOICE_NETWORK_ALLOWLIST: Array[String] = [
	"res://scripts/voice/voice_client.gd",
]

## Files that may construct `AudioStreamMicrophone`. EMPTY BY DESIGN: the game
## captures no audio itself; recognition is the on-device native plugin behind
## `SpeechService`. Adding an entry here requires an update to
## `docs/ALIZ_TUTOR_PRIVACY_REVIEW.md` (data inventory) in the same commit.
const MICROPHONE_ALLOWLIST: Array[String] = []

## Files allowed to contain a URL literal inside a string, and why.
const URL_LITERAL_ALLOWLIST: Array[String] = [
	"res://scripts/tutor/tutor_flags.gd",           # loopback dev default only
	"res://scenes/parent/parent_settings.gd",       # Songs for Fun text link, gated
	"res://scripts/tutor/turn/tutor_turn.gd",       # URL markers the validator REJECTS on
	"res://scripts/voice/voice_client.gd",          # validates a server-issued WSS URL
	"res://scripts/voice/test/test_voice_client.gd", # negative/positive URL validation fixtures
]

# -- constants ------------------------------------------------------------------

const SCANNED_DIRS: Array[String] = ["res://scripts", "res://scenes", "res://addons"]
const SCANNED_EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "cfg"]
const PROJECT: String = "res://project.godot"
const PRESETS: String = "res://export_presets.cfg"
const FLAGS: String = "res://scripts/tutor/tutor_flags.gd"
const SPEECH_DIR: String = "res://scripts/speech/"
const IOS_BACKEND: String = "res://scripts/speech/ios_speech_backend.gd"
const PARENT_DIR: String = "res://scenes/parent/"
const TUTOR_DIR: String = "res://scripts/tutor/"

## Provider names, key names and header words. Matched case-insensitively in
## executable code with string contents kept.
## ("meshy" alone is NOT listed: rig profiles and asset folders are named after
## the generator that produced them, which is provenance, not a network call.)
const FORBIDDEN_PROVIDER_TOKENS: Array[String] = [
	"openai", "anthropic", "chatgpt", "gpt-4", "gpt-5",
	"openai_api_key", "meshy_api_key", "anthropic_api_key", "parent_approval_secret",
	"api_key", "apikey", "bearer ", "authorization:",
]

## Provider / cloud hostnames. Never in the client, in any file.
const FORBIDDEN_HOSTS: Array[String] = [
	"api.openai.com", "openai.com", "openai.azure.com", "api.anthropic.com",
	"generativelanguage.googleapis.com", "api.meshy.ai",
	"fly.dev", "workers.dev", "herokuapp.com", "onrender.com", "railway.app",
	"vercel.app", "amazonaws.com", "cloudfunctions.net", "run.app",
]

const URL_SCHEMES: Array[String] = ["http://", "https://", "ws://", "wss://"]

const NETWORK_PRIMITIVES: Array[String] = [
	"HTTPRequest", "HTTPClient", "WebSocketPeer", "WebSocketMultiplayerPeer",
	"StreamPeerTCP", "StreamPeerTLS", "PacketPeerUDP", "PacketPeerDTLS",
	"TCPServer", "UDPServer", "DTLSServer", "ENetConnection", "ENetMultiplayerPeer",
	"WebRTCPeerConnection", "UPNP",
]

const MICROPHONE_PRIMITIVES: Array[String] = ["AudioStreamMicrophone"]
const RECORDING_PRIMITIVES: Array[String] = ["AudioEffectRecord"]

const LAUNCHERS: Array[String] = [
	"shell_open", "shell_show_in_file_manager", "OS.execute", "OS.create_process",
	"create_instance",
]

## Anything that would arm the cloud path or name a secret in a committed
## project file.
const FORBIDDEN_IN_PROJECT_FILES: Array[String] = [
	"--ai-tutor-cloud", "ai_tutor/cloud_enabled=true", "OPENAI", "MESHY_API_KEY",
	"PARENT_APPROVAL_SECRET", "sk-proj-", "Bearer ",
	"permissions/internet=true", "permissions/record_audio=true",
	"permissions/access_network_state=true", "enable_input=true",
]

const NATIVE_SINGLETON_NAME: String = "LittleBuddySpeech"


func test_name() -> String:
	return "tutor_privacy_guards"


func run():
	var failures: Array = []
	failures.append_array(_test_the_scanner_itself())
	failures.append_array(_test_no_provider_or_secret_reference())
	failures.append_array(_test_no_url_literal_outside_allowlist())
	failures.append_array(_test_backend_url_default_is_loopback())
	failures.append_array(_test_microphone_only_inside_speech_service())
	failures.append_array(_test_launchers_only_behind_the_parental_gate())
	failures.append_array(_test_network_primitives_only_on_the_allowlist())
	failures.append_array(_test_allowlisted_files_check_the_flag_first())
	failures.append_array(_test_project_files_carry_no_cloud_switch())
	failures.append_array(_test_backend_env_example_and_gitignore())
	return failures


# -- 0. the scanner, proven before it is trusted ----------------------------

func _test_the_scanner_itself():
	var failures: Array = []
	if _code_of("x = 1 # HTTPRequest in a comment", false).contains("HTTPRequest"):
		failures.append("the scanner reads '#' comments; a doc comment that correctly says 'never HTTPRequest' would fail the suite")
	if _code_of("## OpenAI is never referenced here", true).contains("OpenAI"):
		failures.append("the scanner reads '##' doc comments")
	if not _code_of("var r := HTTPRequest.new()", false).contains("HTTPRequest"):
		failures.append("the scanner cannot see a token in executable code; it is vacuous")
	if _code_of("var s := \"HTTPRequest\"", false).contains("HTTPRequest"):
		failures.append("the API scanner reads string bodies; a message about HTTPRequest must not count as a use")
	if not _code_of("var u := \"https://api.openai.com\"", true).contains("api.openai.com"):
		failures.append("the string scanner cannot see a string literal; the hostname checks below would be blind")
	if _code_of("# https://api.openai.com", true).contains("openai"):
		failures.append("the string scanner reads comments as strings")
	if _files_to_scan().size() < 100:
		failures.append("only %d files found under %s; the sweep is not real" % [_files_to_scan().size(), str(SCANNED_DIRS)])
	return failures


# -- 1. providers, keys, hostnames ------------------------------------------

func _test_no_provider_or_secret_reference():
	var failures: Array = []
	var key_regex: RegEx = RegEx.new()
	key_regex.compile("sk-[A-Za-z0-9_-]{16,}")
	for path: String in _files_to_scan():
		var text: String = _strings_of(path)
		var lowered: String = text.to_lower()
		for token: String in FORBIDDEN_PROVIDER_TOKENS:
			if lowered.contains(token):
				failures.append("%s references '%s'; the game never names a provider, a key or an auth header -- only the backend does" % [path, token])
		for host: String in FORBIDDEN_HOSTS:
			if lowered.contains(host):
				failures.append("%s contains the hostname '%s'; addresses come from TutorFlags.backend_url() only" % [path, host])
		if key_regex.search(text) != null:
			failures.append("%s contains an 'sk-...' shaped literal" % path)
	return failures


func _test_no_url_literal_outside_allowlist():
	var failures: Array = []
	for path: String in _files_to_scan():
		if URL_LITERAL_ALLOWLIST.has(path):
			continue
		var text: String = _strings_of(path)
		for scheme: String in URL_SCHEMES:
			if text.contains(scheme):
				failures.append("%s contains a '%s' literal; only the files in URL_LITERAL_ALLOWLIST may, and a backend address must come from TutorFlags.backend_url()" % [path, scheme])
				break
	return failures


## The committed default must point at the developer's own machine. A production
## hostname baked into the client would make every build "one setting away" from
## talking to a server, and the review has not approved any server.
func _test_backend_url_default_is_loopback():
	var failures: Array = []
	var text: String = _strings_of(FLAGS)
	if text.is_empty():
		return ["could not read %s" % FLAGS]
	var found_default: bool = false
	for line: String in text.split("\n"):
		if not line.contains("DEFAULT_BACKEND_URL"):
			continue
		if not line.contains("="):
			continue
		found_default = true
		if not (line.contains("127.0.0.1") or line.contains("localhost")):
			failures.append("tutor_flags.gd DEFAULT_BACKEND_URL is not loopback: %s" % line.strip_edges())
	if not found_default:
		failures.append("tutor_flags.gd no longer declares DEFAULT_BACKEND_URL; the loopback check is blind")
	if text.contains("https://"):
		failures.append("tutor_flags.gd carries an https:// literal; the client ships with no server address")
	var project_text: String = _read(PROJECT)
	if not project_text.contains("ai_tutor/backend_url=\"\""):
		failures.append("project.godot must commit little_days/ai_tutor/backend_url=\"\" (empty) so no export carries a server address")
	return failures


# -- 2. microphone -------------------------------------------------------------

func _test_microphone_only_inside_speech_service():
	var failures: Array = []
	for path: String in _files_to_scan():
		var code: String = _code_of_file(path)
		for primitive: String in MICROPHONE_PRIMITIVES:
			if code.contains(primitive) and not MICROPHONE_ALLOWLIST.has(path):
				failures.append("%s constructs %s; the game never opens the microphone itself (recognition is the on-device plugin behind SpeechService)" % [path, primitive])
		for primitive: String in RECORDING_PRIMITIVES:
			if code.contains(primitive):
				failures.append("%s uses %s; child audio is never recorded" % [path, primitive])
		# The native speech singleton is reached from exactly one file.
		if path != IOS_BACKEND and _strings_of(path).contains("\"%s\"" % NATIVE_SINGLETON_NAME) and code.contains("get_singleton"):
			failures.append("%s fetches the native speech singleton directly; only %s may" % [path, IOS_BACKEND])
		# `start_listening` on anything other than the SpeechService autoload or
		# a duck-typed `speech` node is a second microphone path.
		if not path.begins_with(SPEECH_DIR) and code.contains("Engine.get_singleton") and code.contains("start_listening"):
			failures.append("%s calls start_listening on an engine singleton; go through SpeechService" % path)
	var project_text: String = _read(PROJECT)
	if project_text.contains("audio/driver/enable_input=true"):
		failures.append("project.godot enables audio input capture; Godot never owns the microphone in this project")
	for allowed: String in MICROPHONE_ALLOWLIST:
		if not allowed.begins_with(TUTOR_DIR):
			failures.append("MICROPHONE_ALLOWLIST entry %s is outside %s" % [allowed, TUTOR_DIR])
	return failures


# -- 3. launchers --------------------------------------------------------------

func _test_launchers_only_behind_the_parental_gate():
	var failures: Array = []
	for path: String in _files_to_scan():
		var code: String = _code_of_file(path)
		for launcher: String in LAUNCHERS:
			if not code.contains(launcher):
				continue
			if not path.begins_with(PARENT_DIR):
				failures.append("%s uses %s; a browser or process launch is reachable from a child-facing file" % [path, launcher])
			elif not (code.contains("ParentalGate") or _strings_of(path).contains("parental_gate")):
				failures.append("%s uses %s but does not instantiate the ParentalGate" % [path, launcher])
	return failures


# -- 4. network primitives -----------------------------------------------------

func _test_network_primitives_only_on_the_allowlist():
	var failures: Array = []
	for allowed: String in NETWORK_ALLOWLIST:
		if not allowed.begins_with(TUTOR_DIR) or not allowed.ends_with(".gd"):
			failures.append("NETWORK_ALLOWLIST entry %s must be a script under %s" % [allowed, TUTOR_DIR])
	for path: String in _files_to_scan():
		if NETWORK_ALLOWLIST.has(path) or IDENTITY_NETWORK_ALLOWLIST.has(path) or VOICE_NETWORK_ALLOWLIST.has(path):
			continue
		var code: String = _code_of_file(path)
		for primitive: String in NETWORK_PRIMITIVES:
			if _contains_word(code, primitive):
				failures.append("%s uses %s and is not on NETWORK_ALLOWLIST (test_tutor_privacy_guards.gd); only the flag-gated tutor client may network" % [path, primitive])
	return failures


## Source-order proof: the flag is read before the first primitive, the address
## comes from `backend_url()`, and the file holds no URL of its own.
func _test_allowlisted_files_check_the_flag_first():
	var failures: Array = []
	for path: String in NETWORK_ALLOWLIST:
		if not FileAccess.file_exists(path):
			continue  # written ahead of the code; skipped until it lands
		var code: String = _code_of_file(path)
		var first_primitive: int = -1
		var primitive_name: String = ""
		for primitive: String in NETWORK_PRIMITIVES:
			var at: int = code.find(primitive)
			if at != -1 and (first_primitive == -1 or at < first_primitive):
				first_primitive = at
				primitive_name = primitive
		if first_primitive == -1:
			continue  # on the list but not networking (yet); nothing to prove
		var flag_at: int = code.find("cloud_enabled()")
		if flag_at == -1:
			failures.append("%s networks but never reads TutorFlags.cloud_enabled()" % path)
		elif flag_at > first_primitive:
			failures.append("%s constructs %s at offset %d before it reads cloud_enabled() at %d; check the flag first" % [path, primitive_name, first_primitive, flag_at])
		if not code.contains("backend_url()"):
			failures.append("%s networks but does not take its address from TutorFlags.backend_url()" % path)
		var strings: String = _strings_of(path)
		for scheme: String in URL_SCHEMES:
			if strings.contains(scheme):
				failures.append("%s carries its own '%s' literal" % [path, scheme])
	for path: String in IDENTITY_NETWORK_ALLOWLIST:
		var strings: String = _strings_of(path)
		for scheme: String in URL_SCHEMES:
			if strings.contains(scheme):
				failures.append("%s carries its own '%s' literal" % [path, scheme])
		if not _read(PROJECT).contains("services/backend_url=\"\""):
			failures.append("project.godot must keep the identity service URL empty until deployment configuration")
	for path: String in VOICE_NETWORK_ALLOWLIST:
		var code: String = _code_of_file(path)
		var strings: String = _strings_of(path)
		if not code.contains("if not is_allowed()"):
			failures.append("%s must reject connection before opening a socket when the voice privacy gate is closed" % path)
		if not code.contains("live_child_audio_enabled and parent_voice_consent"):
			failures.append("%s must require both the child-audio switch and parent consent" % path)
		if not (code.contains("url.begins_with") and strings.contains("wss://")):
			failures.append("%s must accept only server-issued TLS WebSocket URLs" % path)
	return failures


# -- 5. committed project files --------------------------------------------------

func _test_project_files_carry_no_cloud_switch():
	var failures: Array = []
	for file: String in [PROJECT, PRESETS]:
		var text: String = _read(file)
		if text.is_empty():
			failures.append("could not read %s" % file)
			continue
		for needle: String in FORBIDDEN_IN_PROJECT_FILES:
			if text.contains(needle):
				failures.append("%s contains '%s'" % [file, needle])
	var project_text: String = _read(PROJECT)
	if not project_text.contains("ai_tutor/cloud_enabled=false"):
		failures.append("project.godot must commit little_days/ai_tutor/cloud_enabled=false")
	return failures


# -- 6. backend hygiene (only when the backend is in this checkout) --------------

func _test_backend_env_example_and_gitignore():
	var failures: Array = []
	var root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var gitignore: String = _read_abs(root.path_join(".gitignore"))
	if gitignore.is_empty():
		return ["could not read the repository .gitignore"]
	var lines: PackedStringArray = PackedStringArray()
	for raw: String in gitignore.split("\n"):
		lines.append(raw.strip_edges())
	if not (lines.has(".env") or lines.has("backend/.env")):
		failures.append(".gitignore must ignore .env (or backend/.env)")

	var backend_dir: String = root.path_join("backend")
	if not DirAccess.dir_exists_absolute(backend_dir):
		return failures  # backend not merged into this checkout yet
	if not lines.has("backend/data/"):
		failures.append(".gitignore must ignore backend/data/ (sessions, usage, idempotency keys)")
	var env_file: String = backend_dir.path_join(".env")
	if FileAccess.file_exists(env_file):
		failures.append("backend/.env exists in the working tree; it must never be committed -- verify with `git check-ignore backend/.env`")

	var example: String = _read_abs(backend_dir.path_join(".env.example"))
	if example.is_empty():
		failures.append("backend/.env.example is missing or empty; the backend must document its variables by NAME")
		return failures
	var name_only: RegEx = RegEx.new()
	name_only.compile("^[A-Z][A-Z0-9_]*=$")
	for raw: String in example.split("\n"):
		var line: String = raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if name_only.search(line) == null:
			failures.append("backend/.env.example line carries a value or is malformed: '%s'" % line)
	return failures


# -- scanning helpers ------------------------------------------------------------

var _file_cache: PackedStringArray = PackedStringArray()
var _text_cache: Dictionary = {}


func _files_to_scan() -> PackedStringArray:
	if _file_cache.is_empty():
		for directory: String in SCANNED_DIRS:
			_file_cache.append_array(_files_under(directory))
	return _file_cache


func _files_under(directory: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return found
	for file_name: String in dir.get_files():
		var name: String = file_name.trim_suffix(".remap")
		for extension: String in SCANNED_EXTENSIONS:
			if name.ends_with("." + extension):
				found.append("%s/%s" % [directory, name])
				break
	for sub_directory: String in dir.get_directories():
		found.append_array(_files_under("%s/%s" % [directory, sub_directory]))
	found.sort()
	return found


func _read(path: String) -> String:
	if _text_cache.has(path):
		return _text_cache[path]
	var text: String = ""
	if FileAccess.file_exists(path):
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file != null:
			text = file.get_as_text()
			file.close()
	_text_cache[path] = text
	return text


func _read_abs(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Executable code of a file: comments removed and string bodies blanked for a
## script; a scene/resource file as-is (a node type in a .tscn is a real
## dependency and has no comment syntax).
func _code_of_file(path: String) -> String:
	var text: String = _read(path)
	return _code_of(text, false) if path.ends_with(".gd") else text


## Comments removed, string bodies KEPT -- for hostnames and key literals, which
## only ever live inside a string.
func _strings_of(path: String) -> String:
	var text: String = _read(path)
	return _code_of(text, true) if path.ends_with(".gd") else text


static func _code_of(text: String, keep_string_contents: bool) -> String:
	var out: String = ""
	for line: String in text.split("\n"):
		out += _strip_line(line, keep_string_contents) + "\n"
	return out


static func _strip_line(line: String, keep_string_contents: bool) -> String:
	var out: String = ""
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if quote.is_empty():
			if character == "#":
				break
			if character == "\"" or character == "'":
				quote = character
			else:
				out += character
		else:
			if character == "\\":
				index += 1
			elif character == quote:
				quote = ""
			elif keep_string_contents:
				out += character
		index += 1
	return out


## Whole-identifier match, so `HTTPClient` does not fire on `HTTPClientTCP`-style
## names that are themselves listed, and `UPNP` does not fire inside a longer word.
static func _contains_word(code: String, word: String) -> bool:
	var at: int = code.find(word)
	while at != -1:
		var before_ok: bool = at == 0 or not _is_ident(code[at - 1])
		var after: int = at + word.length()
		var after_ok: bool = after >= code.length() or not _is_ident(code[after])
		if before_ok and after_ok:
			return true
		at = code.find(word, at + 1)
	return false


static func _is_ident(character: String) -> bool:
	return character == "_" or character.is_valid_identifier() or character.is_valid_int()
