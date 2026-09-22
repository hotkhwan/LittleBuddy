class_name LittleDaysAccountState
extends RefCounted

signal changed(snapshot: Dictionary)

const TYPE_GUEST := "guest"
const TYPE_PARENT := "parent"
const PROVIDERS: Array[String] = ["apple", "google"]

var _installation_id := ""
var _session: Dictionary = {}


func configure(installation_id: String, session: Dictionary = {}) -> void:
	_installation_id = installation_id
	_session = session.duplicate(true)
	changed.emit(snapshot())


func apply_guest_response(response: Dictionary) -> bool:
	var account_id := String(response.get("guestAccountId", ""))
	# The Worker's /v1/auth/guest reply names the credential `guestToken`
	# (identity e2e 2026-09-22); older shapes are still read.
	var token := String(response.get("guestToken", response.get("sessionToken", response.get("token", ""))))
	if account_id.is_empty() or token.is_empty():
		return false
	_session = {"accountId": account_id, "accountType": TYPE_GUEST, "sessionToken": token,
		"expiresAt": int(response.get("expiresAt", 0))}
	changed.emit(snapshot())
	return true


func apply_link_response(response: Dictionary) -> bool:
	var account_id := String(response.get("parentAccountId", response.get("accountId", "")))
	# /v1/auth/link replies with `parentToken`.
	var token := String(response.get("parentToken", response.get("sessionToken", response.get("token", ""))))
	if account_id.is_empty() or token.is_empty():
		return false
	_session = {"accountId": account_id, "accountType": TYPE_PARENT, "sessionToken": token,
		"expiresAt": int(response.get("expiresAt", 0))}
	changed.emit(snapshot())
	return true


func is_guest() -> bool:
	return String(_session.get("accountType", TYPE_GUEST)) == TYPE_GUEST


func is_linked() -> bool:
	return not _session.is_empty() and not is_guest()


func subscription_action(parent_gate_open: bool) -> Dictionary:
	if not parent_gate_open:
		return {"allowed": false, "action": "show_parent_gate"}
	if is_guest() or _session.is_empty():
		return {"allowed": false, "action": "link_account", "message": "Save progress across devices"}
	return {"allowed": true, "action": "continue_purchase"}


func provider_link_request(provider: String, identity_token: String) -> Dictionary:
	if not PROVIDERS.has(provider) or identity_token.strip_edges().is_empty() or _session.is_empty():
		return {}
	return {"provider": provider, "identityToken": identity_token, "guestAccountId": String(_session.get("accountId", ""))}


func snapshot() -> Dictionary:
	return {"installationId": _installation_id, "accountId": String(_session.get("accountId", "")),
		"accountType": String(_session.get("accountType", TYPE_GUEST)), "linked": is_linked()}


func session_for_persistence() -> Dictionary:
	return _session.duplicate(true)
