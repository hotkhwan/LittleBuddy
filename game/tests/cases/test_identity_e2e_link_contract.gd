extends RefCounted
## Identity e2e, client side, state "guest -> parent link" and the native
## sign-in that is still missing.
##
##   1. The client's link request is `POST /v1/auth/link` with the guest session
##      as bearer and a body of exactly `{provider, identityToken}`; `provider`
##      is only ever `apple` or `google` (no dev provider exists for linking).
##   2. `LittleDaysAccountState.provider_link_request()` refuses an unknown
##      provider, an empty identity token, and a client with no session.
##   3. After a link the state is a parent: `subscription_action()` continues to
##      purchase (behind the gate) and the credential store persists the parent
##      session under the same four keys.
##   4. GAP (characterised): the Worker's link reply carries `parentToken`; the
##      client reads `sessionToken` / `token`, so today the recorded reply is
##      rejected exactly like the guest one.
##   5. There is no native Sign in with Apple / Google Credential Manager
##      adapter anywhere in the game tree: `ParentAccountUx` lists the two
##      buttons, nothing produces an identity token yet. The scan below pins
##      that fact so the doc stays honest until the adapters land.

const AccountState := preload("res://scripts/account/account_state.gd")
const Credentials := preload("res://scripts/account/credential_store.gd")
const Api := preload("res://scripts/account/identity_api.gd")
const ParentUx := preload("res://scripts/account/parent_account_ux.gd")

## The Worker's link reply as observed in cloud/test/identity_e2e.test.ts
## (POST /v1/auth/link, 200). Synthetic ids; the token is not a live credential.
const WORKER_LINK_REPLY := {
	"parentAccountId": "54e4e672-f6fd-49b9-a173-a8407f0ae30d",
	"linkedGuestAccountId": "1cab8220-16ac-422d-a921-8d28592240f4",
	"parentToken": "pt1.eyJwaWQiOiI1NGU0ZTY3Mi1mNmZkLTQ5YjktYTE3My1hODQwN2YwYWUzMGQiLCJpYXQiOjE3OTAwNjk1ODgsImV4cCI6MTc5MjY2MTU4OH0.6a038f851022ad2fe29f7c1e3d53cc2f50c63a0f8a13ee9632f9e1f72c968b8f",
	"provider": "apple",
	"mergeStatus": "complete",
}

const NATIVE_SIGN_IN_TOKENS: Array[String] = [
	"ASAuthorizationAppleIDProvider", "ASAuthorizationController", "AuthenticationServices",
	"CredentialManager", "GetGoogleIdOption", "GoogleIdTokenCredential", "GIDSignIn",
]
const SCAN_ROOTS: Array[String] = ["res://scripts", "res://scenes", "res://ios", "res://android", "res://addons"]
const SCAN_EXTENSIONS: Array[String] = [".gd", ".tscn", ".swift", ".m", ".mm", ".kt", ".java", ".gdip", ".cfg"]


func test_name() -> String:
	return "identity_e2e_link_contract"


func run():
	var failures: Array = []
	failures.append_array(_test_link_request_contract())
	failures.append_array(_test_link_reply_and_parent_state())
	failures.append_array(_test_native_sign_in_adapters_are_absent())
	return failures


func _test_link_request_contract():
	var failures: Array = []
	var api: Node = Api.new()
	var shape: Dictionary = api.request_shape("link", {"provider": "apple", "identityToken": "eyJ.synthetic"})
	if shape.get("path") != "/v1/auth/link" or shape.get("method") != HTTPClient.METHOD_POST:
		failures.append("link request is not POST /v1/auth/link")
	var keys: Array = (shape.get("body", {}) as Dictionary).keys()
	keys.sort()
	if keys != ["identityToken", "provider"]:
		failures.append("link body is not exactly {provider, identityToken}: %s" % str(keys))
	if api.link_account("gt1.x", "apple", "eyJ.synthetic"):
		failures.append("link_account() claimed to send with no backend configured")
	api.free()
	var state: RefCounted = AccountState.new()
	state.configure("6f188783-5bbd-4f50-a089-3776d7b66a50")
	if not state.provider_link_request("apple", "eyJ.synthetic").is_empty():
		failures.append("a client without a guest session built a link request")
	state.apply_guest_response({"guestAccountId": "1cab8220-16ac-422d-a921-8d28592240f4", "sessionToken": "gt1.x"})
	for provider: String in ["dev", "facebook", "", "APPLE"]:
		if not state.provider_link_request(provider, "eyJ.synthetic").is_empty():
			failures.append("provider %s was accepted for linking" % provider)
	if not state.provider_link_request("apple", "   ").is_empty():
		failures.append("an empty identity token was accepted for linking")
	var req: Dictionary = state.provider_link_request("google", "eyJ.synthetic")
	if req.get("provider") != "google" or req.get("identityToken") != "eyJ.synthetic":
		failures.append("link request lost its provider or token: %s" % str(req))
	if req.has("email") or req.has("installationId"):
		failures.append("link request carries data the route does not take: %s" % str(req.keys()))
	return failures


func _test_link_reply_and_parent_state():
	var failures: Array = []
	var state: RefCounted = AccountState.new()
	state.configure("6f188783-5bbd-4f50-a089-3776d7b66a50")
	state.apply_guest_response({"guestAccountId": "1cab8220-16ac-422d-a921-8d28592240f4", "sessionToken": "gt1.x"})
	# What the client was written against.
	if not state.apply_link_response({"parentAccountId": WORKER_LINK_REPLY["parentAccountId"], "sessionToken": "pt1.x"}):
		failures.append("client-shaped link reply rejected")
	if not state.is_linked() or state.is_guest():
		failures.append("linked state still reads as guest")
	var action: Dictionary = state.subscription_action(true)
	if not bool(action.get("allowed", false)) or action.get("action") != "continue_purchase":
		failures.append("a linked parent was not allowed to continue: %s" % str(action))
	if state.subscription_action(false).get("action") != "show_parent_gate":
		failures.append("a linked parent skipped the parental gate")
	var view: Dictionary = ParentUx.view(state)
	if not bool(view.get("linked", false)) or not (view.get("providers", [1]) as Array).is_empty():
		failures.append("linked parent is still offered sign-in buttons: %s" % str(view))
	var snapshot: Dictionary = state.snapshot()
	if snapshot.get("accountType") != "parent" or snapshot.get("accountId") != WORKER_LINK_REPLY["parentAccountId"]:
		failures.append("snapshot does not describe the parent account: %s" % str(snapshot))
	# Restore on a second device is the same session shape, persisted under the same whitelist.
	var path := "/tmp/little-days-e2e-parent-session-%d.dat" % randi()
	var store: RefCounted = Credentials.new(path, "e2e-test-password")
	store.save_session(state.session_for_persistence())
	var restored: Dictionary = store.load_session()
	store.clear()
	if restored.get("accountType") != "parent" or restored.get("accountId") != WORKER_LINK_REPLY["parentAccountId"]:
		failures.append("parent session did not survive the credential store: %s" % str(restored))
	var second: RefCounted = AccountState.new()
	second.configure("another-installation", restored)
	if not second.is_linked():
		failures.append("a restored parent session on a second installation did not read as linked")
	# What the Worker actually answers: the client must accept it and become linked.
	var fresh: RefCounted = AccountState.new()
	fresh.configure("6f188783-5bbd-4f50-a089-3776d7b66a50")
	fresh.apply_guest_response({"guestAccountId": "1cab8220-16ac-422d-a921-8d28592240f4", "guestToken": "gt1.x"})
	if not fresh.apply_link_response(WORKER_LINK_REPLY.duplicate(true)):
		failures.append("the Worker /v1/auth/link reply (parentToken) must be accepted by apply_link_response")
	elif not fresh.is_linked():
		failures.append("an accepted link reply must leave the account state linked")
	return failures


func _test_native_sign_in_adapters_are_absent():
	var failures: Array = []
	var found: Array = []
	for root: String in SCAN_ROOTS:
		_scan(root, found)
	if not found.is_empty():
		failures.append("GAP CLOSED: native sign-in adapter code found (%s); update this case and docs/IDENTITY_E2E_VERIFICATION.md" % str(found))
	else:
		print("  [identity_e2e] GAP: no Sign in with Apple / Google Credential Manager adapter exists in the game tree; ParentAccountUx offers two buttons that cannot yet produce an identityToken")
	var view: Dictionary = ParentUx.view(null)
	var ids: Array = []
	for entry: Variant in view.get("providers", []):
		ids.append((entry as Dictionary).get("id"))
	if ids != ["apple", "google"]:
		failures.append("ParentAccountUx providers drifted: %s" % str(ids))
	return failures


func _scan(dir_path: String, found: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with(".") and entry != "bin" and entry != "build":
				_scan(full, found)
		else:
			var scan := false
			for ext: String in SCAN_EXTENSIONS:
				if entry.ends_with(ext):
					scan = true
					break
			if scan and not full.begins_with("res://tests/"):
				var text := FileAccess.get_file_as_string(full)
				for token: String in NATIVE_SIGN_IN_TOKENS:
					if text.contains(token):
						found.append(full)
						break
		entry = dir.get_next()
	dir.list_dir_end()
