extends RefCounted
## Identity e2e, client side, state "guest -> paid purchase blocked".
##
## A guest (no linked parent account) cannot reach a store from this app, and
## even a reply from the backend cannot turn Family Club on for one:
##
##   1. `LittleDaysAccountState.subscription_action()` for a guest is
##      `link_account`, never `continue_purchase`; `ParentAccountUx` keeps the
##      whole thing out of the child UI.
##   2. Every gateway the factory can hand out (iOS, Android, desktop mock)
##      answers `disabled` from `purchase()` because
##      `little_days/billing/purchases_enabled` is committed false; `PurchaseFlow`
##      maps that to outcome `disabled` and no verify request is built.
##   3. The recorded replies of the live dev Worker for a guest installation
##      (`POST /v1/billing/verify`: 403 not_approved, 503 billing_disabled,
##      403 mock_not_allowed; `GET /v1/me/purchase-identity`: 403
##      parent_account_required) all land in `verify_failed`, and the store
##      entitlement provider stays on Free Starter after each one.

const AccountState := preload("res://scripts/account/account_state.gd")
const ParentUx := preload("res://scripts/account/parent_account_ux.gd")
const Factory := preload("res://scripts/entitlement/store/store_gateway_factory.gd")
const StoreGateway := preload("res://scripts/entitlement/store/store_gateway.gd")
const StoreProducts := preload("res://scripts/entitlement/store/store_products.gd")
const BillingFlags := preload("res://scripts/entitlement/store/billing_flags.gd")
const PurchaseFlow := preload("res://scripts/entitlement/store/purchase_flow.gd")
const VerifyClient := preload("res://scripts/entitlement/store/billing_verify_client.gd")
const StoreProvider := preload("res://scripts/entitlement/store_entitlement_provider.gd")
const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")

const NOW: int = 1_790_069_636  # 2026-09-22, unix seconds

## Recorded 2026-09-22 from https://little-days-api-dev.hotkhwan.workers.dev for a
## guest installation (synthetic). [http_status, body_text].
const LIVE_GUEST_BILLING_REPLIES: Array = [
	# POST /v1/billing/verify with the guest token as the only credential
	[403, '{"error":{"code":"not_approved","message":"The parent sign-in has expired. Please sign in again."}}'],
	# POST /v1/billing/verify store=apple|google with a parent approval, purchases off server side
	[503, '{"ok":false,"code":"billing_disabled","message":"billing is not enabled on this server"}'],
	# POST /v1/billing/verify store=mock, BILLING_DEV_MODE unset
	[403, '{"ok":false,"code":"mock_not_allowed","message":"the mock store exists only in dev mode"}'],
	# handleVerify with a vouched Apple receipt for a guest installation (Worker test pool)
	[403, '{"ok":false,"code":"parent_account_required","message":"link a parent account before purchasing"}'],
	# GET /v1/me/purchase-identity with the guest token
	[403, '{"error":{"code":"parent_account_required","message":"Link a parent account before purchasing."}}'],
]


class Recorder extends RefCounted:
	var outcomes: Array = []
	var decisions: Array = []
	var failures: Array = []
	func on_flow(outcome: Dictionary) -> void:
		outcomes.append(outcome)
	func on_decision(decision: Dictionary) -> void:
		decisions.append(decision)
	func on_verify_failed(failure: Dictionary) -> void:
		failures.append(failure)


class Transport extends RefCounted:
	var requests: Array = []
	var reply: Array = [0, ""]
	func send(method: String, path: String, body: Dictionary, on_done: Callable) -> void:
		requests.append({"method": method, "path": path, "body": body.duplicate(true)})
		on_done.call(int(reply[0]), String(reply[1]))


func test_name() -> String:
	return "identity_e2e_guest_purchase_blocked"


func run():
	var failures: Array = []
	failures.append_array(_test_guest_account_state_routes_to_link_not_purchase())
	failures.append_array(_test_every_gateway_answers_disabled_for_a_guest())
	failures.append_array(_test_recorded_worker_refusals_never_grant())
	return failures


func _test_guest_account_state_routes_to_link_not_purchase():
	var failures: Array = []
	var state: RefCounted = AccountState.new()
	state.configure("6f188783-5bbd-4f50-a089-3776d7b66a50")
	# No session at all (offline, never registered): still no purchase path.
	var none: Dictionary = state.subscription_action(true)
	if bool(none.get("allowed", true)) or none.get("action") != "link_account":
		failures.append("an unregistered installation was routed to purchase: %s" % str(none))
	state.apply_guest_response({"guestAccountId": "1cab8220-16ac-422d-a921-8d28592240f4", "sessionToken": "gt1.x"})
	var guest: Dictionary = state.subscription_action(true)
	if bool(guest.get("allowed", true)) or guest.get("action") != "link_account":
		failures.append("a guest was routed to purchase: %s" % str(guest))
	if state.subscription_action(false).get("action") != "show_parent_gate":
		failures.append("the parental gate was skipped for a guest")
	var tap: Dictionary = ParentUx.subscription_tap(state, true)
	if bool(tap.get("allowed", true)):
		failures.append("ParentAccountUx allowed a guest subscription tap")
	var view: Dictionary = ParentUx.view(state)
	if bool(view.get("showInChildUi", true)):
		failures.append("account linking is shown in the child UI")
	var providers: Array = view.get("providers", [])
	if providers.size() != 2 or providers[0].get("id") != "apple" or providers[1].get("id") != "google":
		failures.append("guest link offer is not exactly Apple + Google: %s" % str(providers))
	if ParentUx.subscription_tap(null, true).get("action") != "show_parent_gate":
		failures.append("a missing account state did not fall back to the parental gate")
	return failures


func _test_every_gateway_answers_disabled_for_a_guest():
	var failures: Array = []
	if BillingFlags.purchases_enabled():
		failures.append("little_days/billing/purchases_enabled is true in this environment")
	var product: String = StoreProducts.FAMILY_MONTHLY
	for os_name: String in ["iOS", "Android", "macOS", "Windows", "Linux"]:
		var gateway: RefCounted = Factory.for_platform(os_name)
		var started: Dictionary = gateway.purchase(product)
		if started.get("status") != StoreGateway.STATUS_DISABLED:
			failures.append("%s gateway (%s) did not answer disabled: %s" % [os_name, gateway.gateway_id(), str(started)])
		if gateway.is_available() and os_name in ["iOS", "Android"]:
			failures.append("%s store adapter reports a live SDK in the test runner" % os_name)
		var restore: Dictionary = gateway.restore_purchases()
		if os_name in ["iOS", "Android"] and restore.get("status") != StoreGateway.STATUS_UNAVAILABLE:
			failures.append("%s restore did not report unavailable without a plugin: %s" % [os_name, str(restore)])
	# The orchestration: a grown-up past the gate still gets `disabled`, and no verify request is built.
	var transport := Transport.new()
	var verify: RefCounted = VerifyClient.new()
	verify.configure(Callable(transport, "send"), "6f188783-5bbd-4f50-a089-3776d7b66a50")
	var provider: RefCounted = StoreProvider.new(func() -> int: return NOW)
	var flow: RefCounted = PurchaseFlow.new(Factory.for_platform("iOS"), verify, provider, func() -> int: return NOW)
	var rec := Recorder.new()
	flow.connect("flow_finished", rec.on_flow)
	var result: Dictionary = flow.begin_purchase(product, true)
	if result.get("outcome") != PurchaseFlow.OUTCOME_DISABLED:
		failures.append("PurchaseFlow did not answer disabled for iOS: %s" % str(result))
	if flow.begin_purchase(product, false).get("outcome") != PurchaseFlow.OUTCOME_GATE_CLOSED:
		failures.append("PurchaseFlow started with the parental gate closed")
	if not transport.requests.is_empty():
		failures.append("a disabled purchase still sent %d request(s) to the backend" % transport.requests.size())
	if flow.is_busy():
		failures.append("PurchaseFlow stayed busy after a disabled purchase")
	if provider.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("Family Club became active without a backend decision")
	return failures


func _test_recorded_worker_refusals_never_grant():
	var failures: Array = []
	var receipt := {"store": "apple", "productId": StoreProducts.FAMILY_MONTHLY, "transactionId": "e2e-tx-1",
		"payload": {"transactionId": "e2e-tx-1"}}
	var wire: Dictionary = VerifyClient.request_body(receipt, "6f188783-5bbd-4f50-a089-3776d7b66a50")
	var wire_keys: Array = wire.keys()
	wire_keys.sort()
	if wire_keys != ["clientId", "payload", "productId", "store", "transactionId"]:
		failures.append("verify request shape drifted: %s" % str(wire_keys))
	if wire.get("clientId") != "6f188783-5bbd-4f50-a089-3776d7b66a50":
		failures.append("verify request does not carry the installation id as clientId")
	for reply: Array in LIVE_GUEST_BILLING_REPLIES:
		var transport := Transport.new()
		transport.reply = reply
		var verify: RefCounted = VerifyClient.new()
		verify.configure(Callable(transport, "send"), "6f188783-5bbd-4f50-a089-3776d7b66a50")
		var provider: RefCounted = StoreProvider.new(func() -> int: return NOW)
		var rec := Recorder.new()
		verify.connect("decision_received", rec.on_decision)
		verify.connect("verify_failed", rec.on_verify_failed)
		if not verify.verify(receipt):
			failures.append("verify() refused to send for reply %s" % str(reply[0]))
			continue
		if not rec.decisions.is_empty():
			failures.append("reply %d produced a decision for a guest: %s" % [int(reply[0]), str(rec.decisions)])
		if rec.failures.size() != 1:
			failures.append("reply %d did not fail exactly once: %s" % [int(reply[0]), str(rec.failures)])
			continue
		var failure: Dictionary = rec.failures[0]
		var expected_code: String = VerifyClient.FAIL_BACKEND_UNAVAILABLE if int(reply[0]) >= 500 else VerifyClient.FAIL_REJECTED
		if failure.get("code") != expected_code:
			failures.append("reply %d mapped to %s, expected %s" % [int(reply[0]), str(failure.get("code")), expected_code])
		if int(reply[0]) < 500 and String(reply[1]).contains('"ok":false') and String(failure.get("apiCode", "")).is_empty():
			failures.append("reply %d lost the backend's error code" % int(reply[0]))
		if provider.is_active(EntitlementIds.FAMILY_CLUB) or not provider.decision().is_empty():
			failures.append("reply %d changed the entitlement provider" % int(reply[0]))
		if verify.is_busy():
			failures.append("verify client stayed busy after reply %d" % int(reply[0]))
	return failures
