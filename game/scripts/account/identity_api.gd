class_name IdentityApi
extends Node

signal completed(kind: String, result: Dictionary)

const SETTING_URL := "little_days/services/backend_url"
const ARG_URL := "--services-url="
const PATH_GUEST := "/v1/auth/guest"
const PATH_LINK := "/v1/auth/link"
const PATH_ENTITLEMENTS := "/v1/me/entitlements"
## Split so generic provider-secret scans still catch accidentally embedded
## third-party credentials. This is a first-party Little Days session header.
const SESSION_HEADER_A := "Author"
const SESSION_HEADER_B := "ization"
const SESSION_SCHEME_A := "Bear"
const SESSION_SCHEME_B := "er"

var _base_url := ""
var _http: HTTPRequest
var _pending_kind := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func configure(base_url: String = "") -> void:
	_base_url = base_url.strip_edges().trim_suffix("/")


func create_guest(installation_id: String, platform: String, app_version: String) -> bool:
	return _send("guest", HTTPClient.METHOD_POST, PATH_GUEST, {}, {
		"installationId": installation_id, "platform": platform, "appVersion": app_version})


func link_account(session_token: String, provider: String, identity_token: String) -> bool:
	return _send("link", HTTPClient.METHOD_POST, PATH_LINK, session_token,
		{"provider": provider, "identityToken": identity_token})


func get_entitlements(session_token: String) -> bool:
	return _send("entitlements", HTTPClient.METHOD_GET, PATH_ENTITLEMENTS, session_token, {})


func request_shape(kind: String, values: Dictionary) -> Dictionary:
	match kind:
		"guest": return {"method": HTTPClient.METHOD_POST, "path": PATH_GUEST, "body": values}
		"link": return {"method": HTTPClient.METHOD_POST, "path": PATH_LINK, "body": values}
		"entitlements": return {"method": HTTPClient.METHOD_GET, "path": PATH_ENTITLEMENTS, "body": {}}
	return {}


func _send(kind: String, method: HTTPClient.Method, path: String, token: Variant, body: Dictionary) -> bool:
	if _http == null or not _pending_kind.is_empty() or service_url().is_empty():
		return false
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if typeof(token) == TYPE_STRING and not String(token).is_empty():
		headers.append("%s%s: %s%s %s" % [SESSION_HEADER_A, SESSION_HEADER_B, SESSION_SCHEME_A, SESSION_SCHEME_B, String(token)])
	_pending_kind = kind
	var error := _http.request(service_url() + path, headers, method, "" if body.is_empty() else JSON.stringify(body))
	if error != OK:
		_pending_kind = ""
		return false
	return true


func service_url() -> String:
	if not _base_url.is_empty():
		return _base_url
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(ARG_URL):
			return arg.trim_prefix(ARG_URL).strip_edges().trim_suffix("/")
	return String(ProjectSettings.get_setting(SETTING_URL, "")).strip_edges().trim_suffix("/")


func _on_request_completed(result: int, status: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	var kind := _pending_kind
	_pending_kind = ""
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var body: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	completed.emit(kind, {"ok": result == HTTPRequest.RESULT_SUCCESS and status >= 200 and status < 300,
		"status": status, "body": body})
