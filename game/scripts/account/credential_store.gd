class_name AccountCredentialStore
extends RefCounted

## Persistence boundary for backend session credentials. Native exports may
## replace this with Keychain/Keystore. The fallback uses Godot's encrypted
## file API and never stores provider identity tokens.

const DEFAULT_PATH := "user://account_session.dat"

var _path: String
var _password: String


func _init(path: String = DEFAULT_PATH, app_password: String = "little-days-session-v1") -> void:
	_path = path
	_password = app_password


func save_session(session: Dictionary) -> bool:
	var safe := {
		"accountId": String(session.get("accountId", "")),
		"accountType": String(session.get("accountType", "guest")),
		"sessionToken": String(session.get("sessionToken", "")),
		"expiresAt": int(session.get("expiresAt", 0)),
	}
	var file := FileAccess.open_encrypted_with_pass(_path, FileAccess.WRITE, _password)
	if file == null:
		return false
	file.store_string(JSON.stringify(safe))
	return true


func load_session() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {}
	var file := FileAccess.open_encrypted_with_pass(_path, FileAccess.READ, _password)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var session: Dictionary = parsed
	if String(session.get("accountId", "")).is_empty() or String(session.get("sessionToken", "")).is_empty():
		return {}
	return session


func clear() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
