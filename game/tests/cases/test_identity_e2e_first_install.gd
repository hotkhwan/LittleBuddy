extends RefCounted
## Identity e2e, client side, state "first install -> guest".
##
## What the Godot client does on a fresh install, verified against the recorded
## reply of the live dev Worker (docs/IDENTITY_E2E_VERIFICATION.md):
##
##   1. `InstallationIdentity` mints a random UUID v4 and stores ONLY that id
##      (plus a schema version) in `user://installation.json`. The script reads
##      no device / vendor / advertising / network identifier.
##   2. `AccountCredentialStore` persists the backend session encrypted and
##      whitelists four keys; a provider identity token, an e-mail or a child
##      name handed to it is dropped, never written.
##   3. `IdentityApi` posts `{installationId, platform, appVersion}` to
##      `POST /v1/auth/guest` and nothing else; with no backend URL configured
##      (every committed build: `little_days/services/backend_url=""`) it sends
##      nothing at all.
##   4. Local play never touches the account layer: no gameplay script or scene
##      references it, so a guest with no account and no network plays the whole
##      offline game (the rest of this suite is that evidence).
##   5. GAP (characterised, not fixed here): the Worker answers `guestToken`,
##      `LittleDaysAccountState.apply_guest_response()` reads `sessionToken` /
##      `token`, so the live reply is rejected by the client today.

const Installation := preload("res://scripts/account/installation_identity.gd")
const Credentials := preload("res://scripts/account/credential_store.gd")
const AccountState := preload("res://scripts/account/account_state.gd")
const Api := preload("res://scripts/account/identity_api.gd")

## Recorded 2026-09-22 from POST https://little-days-api-dev.hotkhwan.workers.dev/v1/auth/guest
## (HTTP 201). Synthetic installation; the token is a spent dev credential.
const LIVE_GUEST_REPLY := {
	"guestAccountId": "1cab8220-16ac-422d-a921-8d28592240f4",
	"installationId": "6f188783-5bbd-4f50-a089-3776d7b66a50",
	"guestToken": "gt1.eyJnaWQiOiIxY2FiODIyMC0xNmFjLTQyMmQtYTkyMS04ZDI4NTkyMjQwZjQiLCJpaWQiOiI2ZjE4ODc4My01YmJkLTRmNTAtYTA4OS0zNzc2ZDdiNjZhNTAiLCJpYXQiOjE3OTAwNjkzNDAsImV4cCI6MTc5MjY2MTM0MH0.f6eaa471b8d3c5228cb3228c2feeec3de5936ade952728d04431248439879eb4",
	"accountType": "guest",
}

const FORBIDDEN_IDENTIFIER_SOURCES: Array[String] = [
	"get_unique_id", "get_model_name", "get_local_addresses", "get_local_interfaces",
	"advertising", "idfa", "idfv", "ANDROID_ID", "serial", "imei", "mac_address",
]
const CREDENTIAL_KEYS: Array[String] = ["accountId", "accountType", "sessionToken", "expiresAt"]
const ACCOUNT_LAYER_TOKENS: Array[String] = [
	"scripts/account/", "InstallationIdentity", "IdentityApi", "LittleDaysAccountState",
	"AccountCredentialStore", "ParentAccountUx",
]


func test_name() -> String:
	return "identity_e2e_first_install"


func run():
	var failures: Array = []
	failures.append_array(_test_installation_identity_is_random_and_local_only())
	failures.append_array(_test_credential_store_whitelists_and_encrypts())
	failures.append_array(_test_guest_request_shape_and_no_network_by_default())
	failures.append_array(_test_gameplay_never_references_the_account_layer())
	failures.append_array(_test_live_guest_reply_against_account_state())
	return failures


func _test_installation_identity_is_random_and_local_only():
	var failures: Array = []
	var path := "/tmp/little-days-e2e-installation-%d.json" % randi()
	var installation: RefCounted = Installation.new(path)
	var first: String = installation.load_or_create()
	if not Installation._looks_like_uuid(first):
		failures.append("installation id is not a UUID: %s" % first)
	if first.length() == 36 and first[14] != "4":
		failures.append("installation id is not version 4: %s" % first)
	if first.length() == 36 and not "89ab".contains(first[19].to_lower()):
		failures.append("installation id variant nibble is not RFC 4122: %s" % first)
	if installation.load_or_create() != first:
		failures.append("installation id changed between launches")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		failures.append("installation file is not a JSON object")
	else:
		var keys: Array = (raw as Dictionary).keys()
		keys.sort()
		if keys != ["installationId", "version"]:
			failures.append("installation file holds more than the id and a version: %s" % str(keys))
	# A second "device" (another file) gets a different id: nothing device-derived is in play.
	var other_path := "/tmp/little-days-e2e-installation-%d.json" % randi()
	var second: String = Installation.new(other_path).load_or_create()
	if second == first:
		failures.append("two installations produced the same id (device-derived?)")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(other_path)
	# Reinstall: the file is gone, a fresh id is minted (accepted by design; the backend treats it as a new guest).
	if installation.load_or_create() == first:
		failures.append("reinstall did not produce a fresh installation id")
	DirAccess.remove_absolute(path)
	# Executable lines only: the script's own comment names what it refuses to read.
	var code_lines: PackedStringArray = PackedStringArray()
	for line: String in FileAccess.get_file_as_string("res://scripts/account/installation_identity.gd").split("\n"):
		if not line.strip_edges().begins_with("#"):
			code_lines.append(line)
	var source := "\n".join(code_lines)
	for token: String in FORBIDDEN_IDENTIFIER_SOURCES:
		if source.contains(token):
			failures.append("installation_identity.gd references a device identifier source: %s" % token)
	return failures


func _test_credential_store_whitelists_and_encrypts():
	var failures: Array = []
	var path := "/tmp/little-days-e2e-session-%d.dat" % randi()
	var store: RefCounted = Credentials.new(path, "e2e-test-password")
	var leaky := {
		"accountId": "guest-e2e", "accountType": "guest", "sessionToken": "gt1.e2e.secret",
		"expiresAt": 1792661340,
		"identityToken": "eyJ.apple.identity", "email": "parent@example.com", "childName": "Nong",
		"installationId": "6f188783-5bbd-4f50-a089-3776d7b66a50",
	}
	if not store.save_session(leaky):
		failures.append("credential store could not write its file")
		return failures
	var loaded: Dictionary = store.load_session()
	var keys: Array = loaded.keys()
	keys.sort()
	var expected: Array = CREDENTIAL_KEYS.duplicate()
	expected.sort()
	if keys != expected:
		failures.append("credential store persisted keys outside the whitelist: %s" % str(keys))
	var file := FileAccess.open(path, FileAccess.READ)
	var bytes := file.get_buffer(file.get_length()).hex_encode()
	file.close()
	for plaintext: String in ["gt1.e2e.secret", "parent@example.com", "Nong", "eyJ.apple.identity"]:
		if bytes.contains(plaintext.to_utf8_buffer().hex_encode()):
			failures.append("credential file contains plaintext: %s" % plaintext)
	store.clear()
	if FileAccess.file_exists(path):
		failures.append("credential store clear() left the file behind")
	if not store.load_session().is_empty():
		failures.append("cleared credential store still returns a session")
	return failures


func _test_guest_request_shape_and_no_network_by_default():
	var failures: Array = []
	var api: Node = Api.new()
	var shape: Dictionary = api.request_shape("guest", {
		"installationId": "6f188783-5bbd-4f50-a089-3776d7b66a50", "platform": "ios", "appVersion": "0.0.0-e2e"})
	if shape.get("path") != "/v1/auth/guest" or shape.get("method") != HTTPClient.METHOD_POST:
		failures.append("guest request is not POST /v1/auth/guest")
	var body_keys: Array = (shape.get("body", {}) as Dictionary).keys()
	body_keys.sort()
	if body_keys != ["appVersion", "installationId", "platform"]:
		failures.append("guest request body is not exactly {installationId, platform, appVersion}: %s" % str(body_keys))
	if api.request_shape("entitlements", {}).get("path") != "/v1/me/entitlements":
		failures.append("entitlement request path changed")
	# Committed builds have no backend URL: the call is refused locally and no request leaves the device.
	if not String(ProjectSettings.get_setting("little_days/services/backend_url", "")).is_empty():
		failures.append("little_days/services/backend_url is set in project.godot; committed builds must stay offline")
	if not api.service_url().is_empty():
		failures.append("IdentityApi resolved a backend URL in the test environment: %s" % api.service_url())
	if api.create_guest("6f188783-5bbd-4f50-a089-3776d7b66a50", "ios", "0.0.0-e2e"):
		failures.append("create_guest() claimed to send with no backend configured")
	api.free()
	return failures


func _test_gameplay_never_references_the_account_layer():
	var failures: Array = []
	var offenders: Array = []
	for root: String in ["res://scripts", "res://scenes"]:
		_scan(root, offenders)
	if not offenders.is_empty():
		failures.append("gameplay files reference the account layer (local play must not need an account): %s" % str(offenders))
	return failures


func _scan(dir_path: String, offenders: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan(full, offenders)
		elif (entry.ends_with(".gd") or entry.ends_with(".tscn")) and not full.begins_with("res://scripts/account/"):
			var text := FileAccess.get_file_as_string(full)
			for token: String in ACCOUNT_LAYER_TOKENS:
				if text.contains(token):
					offenders.append(full)
					break
		entry = dir.get_next()
	dir.list_dir_end()


func _test_live_guest_reply_against_account_state():
	var failures: Array = []
	var state: RefCounted = AccountState.new()
	state.configure(String(LIVE_GUEST_REPLY["installationId"]))
	# What the client was written against.
	if not state.apply_guest_response({"guestAccountId": "g", "sessionToken": "s"}):
		failures.append("client-shaped guest reply rejected")
	if not state.is_guest() or state.is_linked():
		failures.append("guest session did not read as guest")
	if state.subscription_action(true).get("action") != "link_account":
		failures.append("a guest was allowed to continue to purchase")
	if state.subscription_action(false).get("action") != "show_parent_gate":
		failures.append("subscription action skipped the parental gate")
	# What the Worker actually answers (recorded): the client must accept it.
	var fresh: RefCounted = AccountState.new()
	fresh.configure(String(LIVE_GUEST_REPLY["installationId"]))
	if not fresh.apply_guest_response(LIVE_GUEST_REPLY.duplicate(true)):
		failures.append("the live /v1/auth/guest reply (guestToken) must be accepted by apply_guest_response")
	elif not fresh.is_guest():
		failures.append("an accepted guest reply must leave the account state as guest")
	# The persisted session (if it had been accepted) never carries the installation id or PII.
	var persisted: Dictionary = state.session_for_persistence()
	for key: Variant in persisted.keys():
		if not CREDENTIAL_KEYS.has(String(key)):
			failures.append("session_for_persistence() carries an unexpected key: %s" % String(key))
	return failures
