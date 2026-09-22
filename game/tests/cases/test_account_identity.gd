extends RefCounted

const Installation := preload("res://scripts/account/installation_identity.gd")
const Credentials := preload("res://scripts/account/credential_store.gd")
const AccountState := preload("res://scripts/account/account_state.gd")
const Api := preload("res://scripts/account/identity_api.gd")
const ParentUx := preload("res://scripts/account/parent_account_ux.gd")

func test_name() -> String: return "account_identity"

func run():
	var failures: Array = []
	var suffix := str(randi())
	# The sandboxed headless runner cannot write the macOS user-data folder.
	# Production defaults remain user://; isolated tests use the writable temp dir.
	var installation_path := "/tmp/little-days-test-installation-%s.json" % suffix
	var credential_path := "/tmp/little-days-test-session-%s.dat" % suffix
	var installation: RefCounted = Installation.new(installation_path)
	var first: String = installation.load_or_create()
	if first.is_empty() or installation.load_or_create() != first:
		failures.append("installation UUID was not stable across relaunch")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(installation_path))
	if installation.load_or_create() == first:
		failures.append("reinstall semantics did not create a fresh installation UUID")
	var credentials: RefCounted = Credentials.new(credential_path, "test-password")
	var session := {"accountId": "guest-1", "accountType": "guest", "sessionToken": "secret"}
	if not credentials.save_session(session) or credentials.load_session().get("sessionToken") != "secret":
		failures.append("encrypted session did not round-trip")
	var encrypted_file := FileAccess.open(credential_path, FileAccess.READ)
	var encrypted_bytes := encrypted_file.get_buffer(encrypted_file.get_length())
	if encrypted_bytes.hex_encode().contains("secret".to_utf8_buffer().hex_encode()):
		failures.append("session token was stored as plaintext")
	credentials.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(installation_path))
	var state: RefCounted = AccountState.new()
	state.configure(first)
	if not state.apply_guest_response({"guestAccountId": "guest-1", "sessionToken": "s"}): failures.append("guest response rejected")
	if state.subscription_action(true).get("action") != "link_account": failures.append("guest was allowed to purchase")
	var ux: Dictionary = ParentUx.view(state)
	if ux.get("headline") != "Save progress across devices" or ux.get("providers", []).size() != 2 or ux.get("showInChildUi", true):
		failures.append("parent account UX did not explain value and offer Apple/Google only behind parent UI")
	if not state.apply_link_response({"parentAccountId": "parent-1", "sessionToken": "p"}): failures.append("link response rejected")
	if not state.subscription_action(true).get("allowed", false): failures.append("linked parent was not allowed to continue")
	var api: Node = Api.new()
	if api.request_shape("guest", {}).get("path") != "/v1/auth/guest" or api.request_shape("link", {}).get("path") != "/v1/auth/link":
		failures.append("identity API routes are incorrect")
	api.free()
	return failures
