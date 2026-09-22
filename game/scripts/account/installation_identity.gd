class_name InstallationIdentity
extends RefCounted

## Random, app-scoped installation identity. This deliberately never reads a
## device, advertising, network-interface, or vendor identifier.

const DEFAULT_PATH := "user://installation.json"

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


func load_or_create() -> String:
	var existing := load_id()
	if not existing.is_empty():
		return existing
	var installation_id := _uuid_v4()
	_write_json({"installationId": installation_id, "version": 1})
	return installation_id


func load_id() -> String:
	if not FileAccess.file_exists(_path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var value := String((parsed as Dictionary).get("installationId", ""))
	return value if _looks_like_uuid(value) else ""


func _write_json(value: Dictionary) -> bool:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	return true


static func _uuid_v4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


static func _looks_like_uuid(value: String) -> bool:
	if value.length() != 36:
		return false
	var regex := RegEx.new()
	regex.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")
	return regex.search(value) != null
