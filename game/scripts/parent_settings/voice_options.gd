extends RefCounted
## The configured list of Aliz voices a grown-up can pick from
## (`res://content/tutor/voice_options.json`), and which of them can be picked
## in THIS build.
##
## Each option: `{id, label, provider: "device"|"cloud", default, description}`.
## Exactly one option is the default (the first `default: true` device voice,
## or the first device voice if the file forgets). A `cloud` voice is offered
## only while `TutorFlags.cloud_enabled()` is true; in every public build it is
## shown disabled with "when the cloud tutor is available", and a stored cloud
## id falls back to the default so the offline tutor always has a voice.
##
## Read with `FileAccess` + `JSON` (never `load()`); ids are validated as plain
## snake_case so a file edit cannot smuggle a path or a URL into a setting.

const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")

const OPTIONS_PATH: String = "res://content/tutor/voice_options.json"
const PROVIDER_DEVICE: String = "device"
const PROVIDER_CLOUD: String = "cloud"
const CLOUD_NOTE: String = "when the cloud tutor is available"
const MAX_ID_LENGTH: int = 40
const MAX_LABEL_LENGTH: int = 40

const FALLBACK_OPTIONS: Array = [
	{"id": "aliz_bright", "label": "Aliz (bright)", "provider": PROVIDER_DEVICE, "default": true,
		"description": "Cheerful, youthful voice from the bundled voice pack or this device's own speech."},
]

static var _cache: Array = []
static var _loaded: bool = false


## Every configured option, sanitised, in file order. Never empty.
static func options(force_reload: bool = false) -> Array:
	if _loaded and not force_reload:
		return _cache.duplicate(true)
	_cache = sanitise(_read_json(OPTIONS_PATH))
	_loaded = true
	return _cache.duplicate(true)


## Pure: any Variant in, a non-empty list of well-formed options out.
static func sanitise(raw: Variant) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var source: Variant = raw.get("options", null) if typeof(raw) == TYPE_DICTIONARY else raw
	if typeof(source) == TYPE_ARRAY:
		for entry: Variant in (source as Array):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var block: Dictionary = entry
			var id: Variant = block.get("id", "")
			if not is_well_formed_id(id) or seen.has(String(id)):
				continue
			var label: Variant = block.get("label", "")
			if typeof(label) != TYPE_STRING or String(label).strip_edges().is_empty():
				continue
			var provider: String = String(block.get("provider", PROVIDER_DEVICE))
			if provider != PROVIDER_DEVICE and provider != PROVIDER_CLOUD:
				continue
			var description: Variant = block.get("description", "")
			var flagged: Variant = block.get("default", false)
			seen[String(id)] = true
			out.append({
				"id": String(id),
				"label": String(label).strip_edges().left(MAX_LABEL_LENGTH),
				"provider": provider,
				"default": typeof(flagged) == TYPE_BOOL and bool(flagged),
				"description": String(description).strip_edges() if typeof(description) == TYPE_STRING else "",
			})
	if out.is_empty():
		return FALLBACK_OPTIONS.duplicate(true)
	# Exactly one default, and it is a device voice (the offline tutor needs it).
	var default_index: int = -1
	for index: int in range(out.size()):
		if bool(out[index]["default"]) and String(out[index]["provider"]) == PROVIDER_DEVICE:
			default_index = index
			break
	if default_index < 0:
		for index: int in range(out.size()):
			if String(out[index]["provider"]) == PROVIDER_DEVICE:
				default_index = index
				break
	if default_index < 0:
		# Only cloud voices configured: the bundled device voice is added so
		# the offline tutor never ends up voiceless.
		out.push_front(FALLBACK_OPTIONS[0].duplicate(true))
		default_index = 0
	for index: int in range(out.size()):
		out[index]["default"] = index == default_index
	return out


## The id every profile starts with.
static func default_id() -> String:
	for option: Dictionary in options():
		if bool(option["default"]):
			return String(option["id"])
	return String(FALLBACK_OPTIONS[0]["id"])


static func find(voice_id: Variant) -> Dictionary:
	if typeof(voice_id) != TYPE_STRING:
		return {}
	for option: Dictionary in options():
		if String(option["id"]) == String(voice_id):
			return option
	return {}


static func is_known(voice_id: Variant) -> bool:
	return not find(voice_id).is_empty()


## Can this voice be chosen in THIS build? Device voices always; cloud voices
## only with the cloud flag on.
static func is_selectable(voice_id: Variant) -> bool:
	var option: Dictionary = find(voice_id)
	if option.is_empty():
		return false
	if String(option["provider"]) == PROVIDER_CLOUD:
		return TutorFlags.cloud_enabled()
	return true


## The label a disabled cloud option shows, e.g. "Aliz (warm) -- when the cloud
## tutor is available".
static func availability_note(voice_id: Variant) -> String:
	var option: Dictionary = find(voice_id)
	if option.is_empty() or is_selectable(voice_id):
		return ""
	return CLOUD_NOTE


## Plain snake_case: lower-case letters, digits and underscores, starting with a letter.
static func is_well_formed_id(voice_id: Variant) -> bool:
	if typeof(voice_id) != TYPE_STRING:
		return false
	var id: String = String(voice_id)
	if id.is_empty() or id.length() > MAX_ID_LENGTH:
		return false
	if id[0] < "a" or id[0] > "z":
		return false
	for index: int in range(id.length()):
		var character: String = id[index]
		var ok: bool = (character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_"
		if not ok:
			return false
	return true


static func reset_cache() -> void:
	_cache = []
	_loaded = false


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text)
