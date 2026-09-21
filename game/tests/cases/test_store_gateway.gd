extends RefCounted
## The store abstraction and the receipt -> backend -> entitlement flow.
##
## What has to be true:
##   1. With purchases disabled (every committed build) `purchase()` answers
##      `disabled` and the store is NOT called -- not once, on any gateway.
##   2. A store callback alone grants nothing. Only a parsed backend decision,
##      applied by the flow, turns `familyClub` on.
##   3. The provider's cache is bounded: `periodEnd` and the 72 h offline window
##      both close it, and a hand-written save cannot open it.
##   4. Restore runs the same verify path per receipt; a second device under the
##      same store account ends up with the same decision.
##   5. Nothing starts unless the caller says the parental gate is open.
##   6. Apple / Google adapters report `store_unavailable` where no plugin exists.

const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")
const EntitlementService := preload("res://scripts/entitlement/entitlement_service.gd")
const StoreProvider := preload("res://scripts/entitlement/store_entitlement_provider.gd")
const StoreGateway := preload("res://scripts/entitlement/store/store_gateway.gd")
const MockGateway := preload("res://scripts/entitlement/store/mock_store_gateway.gd")
const AppleGateway := preload("res://scripts/entitlement/store/apple_store_gateway.gd")
const GoogleGateway := preload("res://scripts/entitlement/store/google_play_gateway.gd")
const Factory := preload("res://scripts/entitlement/store/store_gateway_factory.gd")
const StoreProducts := preload("res://scripts/entitlement/store/store_products.gd")
const VerifyClient := preload("res://scripts/entitlement/store/billing_verify_client.gd")
const PurchaseFlow := preload("res://scripts/entitlement/store/purchase_flow.gd")
const BillingFlags := preload("res://scripts/entitlement/store/billing_flags.gd")

const NOW: int = 1_790_000_000  # 2026-09-21-ish, unix seconds
const DAY: int = 86_400


## A recorded backend, standing in for POST /v1/billing/verify.
class FakeBackend extends RefCounted:
	var requests: Array = []
	var replies: Array = []  # each: [http_status, body_text]; last one repeats
	var pending: Array = []  # [on_done, status, text] when `hold` is true
	var hold: bool = false

	func transport(method: String, path: String, body: Dictionary, on_done: Callable) -> void:
		requests.append({"method": method, "path": path, "body": body.duplicate(true)})
		var reply: Array = replies.pop_front() if replies.size() > 1 else (replies[0] if not replies.is_empty() else [0, ""])
		if hold:
			pending.append([on_done, reply[0], reply[1]])
			return
		on_done.call(int(reply[0]), String(reply[1]))

	func release_all() -> void:
		var queue: Array = pending.duplicate()
		pending.clear()
		for entry: Array in queue:
			(entry[0] as Callable).call(int(entry[1]), String(entry[2]))


class Clock extends RefCounted:
	var now: int = NOW
	func read() -> int:
		return now


class Recorder extends RefCounted:
	var outcomes: Array = []
	var applied: Array = []
	func on_finished(outcome: Dictionary) -> void:
		outcomes.append(outcome)
	func on_applied(decision: Dictionary) -> void:
		applied.append(decision)
	func last() -> String:
		return String(outcomes.back().get("outcome", "")) if not outcomes.is_empty() else ""


func test_name() -> String:
	return "store_gateway"


func run():
	var failures: Array = []
	failures.append_array(_test_products())
	failures.append_array(_test_disabled_purchases_never_reach_the_store())
	failures.append_array(_test_store_callback_alone_grants_nothing())
	failures.append_array(_test_backend_decision_is_the_only_grant())
	failures.append_array(_test_decision_sanitiser())
	failures.append_array(_test_cache_is_bounded())
	failures.append_array(_test_persistence_round_trip_and_tamper())
	failures.append_array(_test_restore_two_devices())
	failures.append_array(_test_gate_and_busy_rules())
	failures.append_array(_test_failures_change_nothing())
	failures.append_array(_test_platform_adapters_unavailable())
	failures.append_array(_test_service_surface())
	return failures


# -- helpers ------------------------------------------------------------------------

static func _decision_body(status: String, period_end: int, product_id: String = StoreProducts.FAMILY_MONTHLY,
		verified_at: int = NOW, original: String = "orig-1") -> String:
	return JSON.stringify({
		"ok": true,
		"decision": {
			"entitlementId": EntitlementIds.FAMILY_CLUB,
			"status": status,
			"periodEnd": period_end,
			"verifiedAt": verified_at,
			"originalTransactionId": original,
			"store": "mock",
			"productId": product_id,
		},
	})


func _rig(backend: FakeBackend, clock: Clock, allow_purchases: bool = true) -> Dictionary:
	var gateway: RefCounted = MockGateway.new()
	gateway.allow_purchases_for_tests = allow_purchases
	var provider: RefCounted = StoreProvider.new(Callable(clock, "read"))
	var verify: RefCounted = VerifyClient.new()
	verify.configure(Callable(backend, "transport"), "device-a")
	var flow: RefCounted = PurchaseFlow.new(gateway, verify, provider, Callable(clock, "read"))
	var recorder: Recorder = Recorder.new()
	flow.connect("flow_finished", recorder.on_finished)
	flow.connect("entitlement_applied", recorder.on_applied)
	return {"gateway": gateway, "provider": provider, "verify": verify, "flow": flow,
			"recorder": recorder, "service": EntitlementService.new(provider)}


# -- 0. products ----------------------------------------------------------------------

func _test_products():
	var failures: Array = []
	if StoreProducts.FAMILY_MONTHLY != "little_days_family_monthly" \
			or StoreProducts.FAMILY_YEARLY != "little_days_family_yearly":
		failures.append("product ids drifted from the owner's decision: %s" % str(StoreProducts.ALL))
	for id: String in StoreProducts.ALL:
		if StoreProducts.entitlement_for(id) != EntitlementIds.FAMILY_CLUB:
			failures.append("%s does not map to familyClub" % id)
	if StoreProducts.is_known("little_days_gold") or StoreProducts.is_known(null) \
			or not StoreProducts.entitlement_for("x").is_empty():
		failures.append("an unknown product id was accepted")
	return failures


# -- 1. disabled ----------------------------------------------------------------------

func _test_disabled_purchases_never_reach_the_store():
	var failures: Array = []
	if BillingFlags.purchases_enabled():
		return ["purchases are enabled in the test run; this case is meaningless"]
	var mock: RefCounted = MockGateway.new()  # allow_purchases_for_tests stays false
	var fired: Array = []
	mock.connect("purchase_updated", func(receipt: Dictionary) -> void: fired.append(receipt))
	var result: Dictionary = mock.purchase(StoreProducts.FAMILY_MONTHLY)
	if String(result.get("status", "")) != StoreGateway.STATUS_DISABLED:
		failures.append("a disabled build's purchase() answered %s, not disabled" % str(result))
	if not mock.calls.is_empty():
		failures.append("a disabled purchase still reached the store: %s" % str(mock.calls))
	if not fired.is_empty():
		failures.append("a disabled purchase emitted purchase_updated")
	# The base class rule holds for the real adapters too: no singleton, no flag,
	# and purchase() must not even get as far as asking for the singleton.
	for adapter: RefCounted in [AppleGateway.new(), GoogleGateway.new()]:
		var outcome: Dictionary = adapter.purchase(StoreProducts.FAMILY_YEARLY)
		if String(outcome.get("status", "")) != StoreGateway.STATUS_DISABLED:
			failures.append("%s.purchase() answered %s with purchases disabled"
					% [adapter.gateway_id(), str(outcome)])
	# And the flow reports it as an outcome a grown-up screen can print.
	var rig: Dictionary = _rig(FakeBackend.new(), Clock.new(), false)
	var flow_result: Dictionary = rig["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
	if String(flow_result.get("outcome", "")) != PurchaseFlow.OUTCOME_DISABLED:
		failures.append("the flow did not report 'disabled': %s" % str(flow_result))
	if rig["flow"].is_busy():
		failures.append("the flow stayed busy after a disabled purchase")
	if rig["service"].is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("familyClub is active after a disabled purchase")
	return failures


# -- 2. store callback alone --------------------------------------------------------------

func _test_store_callback_alone_grants_nothing():
	var failures: Array = []
	var clock: Clock = Clock.new()
	var backend: FakeBackend = FakeBackend.new()
	backend.replies = [[0, ""]]  # the backend is unreachable
	var rig: Dictionary = _rig(backend, clock)
	rig["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
	if rig["gateway"].calls.size() != 1 or String(rig["gateway"].calls[0]["call"]) != "purchase":
		failures.append("the mock store was not asked to purchase exactly once: %s" % str(rig["gateway"].calls))
	if backend.requests.size() != 1:
		failures.append("the receipt was not forwarded to the backend once (%d)" % backend.requests.size())
	if rig["service"].is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("familyClub became active from the store's callback with no backend answer")
	if rig["recorder"].last() != PurchaseFlow.OUTCOME_FAILED:
		failures.append("an unreachable backend did not end the flow as failed: %s" % str(rig["recorder"].outcomes))
	if not rig["recorder"].applied.is_empty():
		failures.append("entitlement_applied fired without a decision")
	# Feeding a receipt straight into the provider does nothing: there is no such method.
	for method: String in ["apply_receipt", "grant", "set_active", "purchase"]:
		if rig["provider"].has_method(method):
			failures.append("the store provider exposes %s()" % method)
	return failures


# -- 3. the backend decision ----------------------------------------------------------------

func _test_backend_decision_is_the_only_grant():
	var failures: Array = []
	var clock: Clock = Clock.new()
	var backend: FakeBackend = FakeBackend.new()
	backend.replies = [[200, _decision_body("active", NOW + 30 * DAY)]]
	var rig: Dictionary = _rig(backend, clock)
	var result: Dictionary = rig["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
	if String(result.get("status", "")) != StoreGateway.STATUS_STARTED:
		failures.append("an enabled mock purchase did not start: %s" % str(result))
	if rig["recorder"].last() != PurchaseFlow.OUTCOME_VERIFIED:
		failures.append("the flow did not end verified: %s" % str(rig["recorder"].outcomes))
	if not rig["service"].is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the backend said active and the service still says no")
	if not rig["service"].is_active(EntitlementIds.FREE_STARTER):
		failures.append("Free Starter was lost")
	# The wire shape.
	var request: Dictionary = backend.requests[0]
	if String(request["method"]) != "POST" or String(request["path"]) != "/v1/billing/verify":
		failures.append("the receipt went to %s %s" % [request["method"], request["path"]])
	var body: Dictionary = request["body"]
	for key: String in ["store", "productId", "transactionId", "payload", "clientId"]:
		if not body.has(key):
			failures.append("the verify body lacks '%s': %s" % [key, str(body)])
	if String(body.get("store", "")) != "mock" or String(body.get("transactionId", "")) != "mock-txn-1":
		failures.append("the verify body is not the mock receipt: %s" % str(body))
	if body.has("entitlementId") or body.has("entitlement") or body.has("status"):
		failures.append("the client sent an entitlement claim to the backend: %s" % str(body))
	# The grown-up status line.
	var status: Dictionary = rig["service"].subscription_status()
	if String(status.get("status", "")) != "active" or int(status.get("periodEnd", 0)) != NOW + 30 * DAY:
		failures.append("subscription_status() is %s" % str(status))
	# Revocation (a refund) turns it off again through the same path.
	backend.replies = [[200, _decision_body("revoked", NOW + 30 * DAY)]]
	rig["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
	if rig["service"].is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a revoked decision left familyClub active")
	if String(rig["service"].subscription_status().get("status", "")) != "revoked":
		failures.append("subscription_status() does not say revoked")
	# Expired, likewise; grace grants.
	backend.replies = [[200, _decision_body("expired", NOW - DAY)]]
	rig["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
	if rig["service"].is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("an expired decision left familyClub active")
	backend.replies = [[200, _decision_body("grace", NOW + 3 * DAY)]]
	rig["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
	if not rig["service"].is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a grace decision does not grant")
	# describe() stays honest: purchasing is not available even with a decision held.
	var described: Dictionary = rig["service"].describe()
	if bool(described.get("purchasingAvailable", true)):
		failures.append("describe() says purchasing is available in a disabled build")
	return failures


# -- 4. sanitiser -------------------------------------------------------------------------

func _test_decision_sanitiser():
	var failures: Array = []
	var good: Dictionary = {"entitlementId": "familyClub", "status": "active", "periodEnd": NOW + DAY,
			"verifiedAt": NOW, "productId": StoreProducts.FAMILY_YEARLY}
	if StoreProvider.sanitise_decision(good).is_empty():
		failures.append("a well-formed decision was rejected")
	var bad: Array = [
		null, "active", [], {},
		{"entitlementId": "freeStarter", "status": "active", "periodEnd": NOW + DAY, "productId": StoreProducts.FAMILY_MONTHLY},
		{"entitlementId": "gold", "status": "active", "periodEnd": NOW + DAY, "productId": StoreProducts.FAMILY_MONTHLY},
		{"entitlementId": "familyClub", "status": "paid", "periodEnd": NOW + DAY, "productId": StoreProducts.FAMILY_MONTHLY},
		{"entitlementId": "familyClub", "status": "active", "periodEnd": NOW + DAY, "productId": "little_days_gold"},
		{"entitlementId": "familyClub", "status": "active", "periodEnd": NOW + DAY},
	]
	for entry: Variant in bad:
		if not StoreProvider.sanitise_decision(entry).is_empty():
			failures.append("a malformed decision was accepted: %s" % str(entry))
	var odd: Dictionary = StoreProvider.sanitise_decision({"entitlementId": "familyClub", "status": "active",
			"periodEnd": "soon", "verifiedAt": -5, "productId": StoreProducts.FAMILY_MONTHLY,
			"originalTransactionId": 42, "store": "x".repeat(400)})
	if int(odd.get("periodEnd", -1)) != 0 or int(odd.get("verifiedAt", -1)) != 0 \
			or String(odd.get("originalTransactionId", "?")) != "" or String(odd.get("store", "")).length() > 128:
		failures.append("junk fields were not neutralised: %s" % str(odd))
	var provider: RefCounted = StoreProvider.new()
	if provider.apply_backend_decision({"entitlementId": "familyClub", "status": "active"}):
		failures.append("apply_backend_decision() accepted a decision with no product")
	if provider.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a rejected decision granted")
	return failures


# -- 5. bounded cache -------------------------------------------------------------------

func _test_cache_is_bounded():
	var failures: Array = []
	var clock: Clock = Clock.new()
	var provider: RefCounted = StoreProvider.new(Callable(clock, "read"))
	provider.apply_backend_decision({"entitlementId": "familyClub", "status": "active",
			"periodEnd": NOW + 30 * DAY, "verifiedAt": NOW, "productId": StoreProducts.FAMILY_MONTHLY}, NOW)
	if not provider.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("fresh decision does not grant")
	clock.now = NOW + BillingFlags.OFFLINE_CACHE_SECONDS - 1
	if not provider.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the decision stopped granting before the offline window closed")
	clock.now = NOW + BillingFlags.OFFLINE_CACHE_SECONDS + 1
	if provider.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("72 h offline and familyClub is still on; the cache is not bounded")
	if String(provider.subscription_status().get("status", "")) != "expired":
		failures.append("an aged-out decision does not read as expired: %s" % str(provider.subscription_status()))
	# A short period ends first.
	clock.now = NOW
	provider.apply_backend_decision({"entitlementId": "familyClub", "status": "active",
			"periodEnd": NOW + 3600, "verifiedAt": NOW, "productId": StoreProducts.FAMILY_MONTHLY}, NOW)
	clock.now = NOW + 3601
	if provider.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("familyClub outlived periodEnd")
	# A decision "verified in the future" cannot stretch the window.
	clock.now = NOW
	provider.apply_backend_decision({"entitlementId": "familyClub", "status": "active",
			"periodEnd": NOW + 30 * DAY, "verifiedAt": NOW + 10 * DAY, "productId": StoreProducts.FAMILY_MONTHLY}, NOW)
	if int(provider.decision().get("verifiedAt", 0)) != NOW:
		failures.append("a future verifiedAt was not clamped to now")
	return failures


# -- 6. persistence -----------------------------------------------------------------------

class FakeSave extends RefCounted:
	var settings: Dictionary = {}
	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return settings.get(key, default_value)
	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value


func _test_persistence_round_trip_and_tamper():
	var failures: Array = []
	var clock: Clock = Clock.new()
	var save: FakeSave = FakeSave.new()

	var provider: RefCounted = StoreProvider.new(Callable(clock, "read"))
	provider.apply_backend_decision({"entitlementId": "familyClub", "status": "active",
			"periodEnd": NOW + 30 * DAY, "verifiedAt": NOW, "productId": StoreProducts.FAMILY_MONTHLY}, NOW)
	var writer: RefCounted = EntitlementService.new(provider)
	writer.save_to(save)
	var stored: Dictionary = save.settings.get(EntitlementService.SETTING_KEY, {})
	if not stored.has("providerState"):
		failures.append("the store provider's decision was not persisted")
	if String(stored.get("providerId", "")) != "store":
		failures.append("the save is tagged %s" % str(stored.get("providerId")))

	# Same provider, restart, still inside the window: granted with no network.
	var reader_provider: RefCounted = StoreProvider.new(Callable(clock, "read"))
	var reader: RefCounted = EntitlementService.new(reader_provider)
	reader.load_from(save)
	if not reader.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the decision did not survive a restart")
	# ...and after the window it is just an expired decision.
	clock.now = NOW + BillingFlags.OFFLINE_CACHE_SECONDS + 1
	if reader.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a stale persisted decision still grants")
	clock.now = NOW

	# The offline provider never reads store state; a store cache is not its cache.
	var offline: RefCounted = EntitlementService.new()
	offline.load_from(save)
	if offline.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the offline provider honoured a store-tagged save")
	# The offline provider's own save shape is untouched (no providerState key).
	var plain: FakeSave = FakeSave.new()
	EntitlementService.new().save_to(plain)
	if (plain.settings.get(EntitlementService.SETTING_KEY, {}) as Dictionary).has("providerState"):
		failures.append("the offline provider's save grew a providerState key")

	# Tampering: the service's `active` list is never believed for the store,
	# and a hand-written decision with a future verifiedAt or a bad product fails.
	var tampered: RefCounted = EntitlementService.new(StoreProvider.new(Callable(clock, "read")))
	tampered.from_dict({"stateVersion": 1, "providerId": "store", "active": ["familyClub"]})
	if tampered.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a hand-written active list granted familyClub through the store provider")
	tampered.from_dict({"stateVersion": 1, "providerId": "store", "active": [],
			"providerState": {"stateVersion": 1, "decision": {"entitlementId": "familyClub",
			"status": "active", "periodEnd": NOW + 365 * DAY, "verifiedAt": NOW, "productId": "little_days_gold"}}})
	if tampered.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a hand-written decision for an unknown product granted")
	tampered.from_dict({"stateVersion": 1, "providerId": "store", "active": [],
			"providerState": {"stateVersion": 1, "decision": {"entitlementId": "familyClub",
			"status": "active", "periodEnd": NOW + 365 * DAY, "verifiedAt": NOW - 30 * DAY,
			"productId": StoreProducts.FAMILY_MONTHLY}}})
	if tampered.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a hand-written decision older than the offline window granted")
	return failures


# -- 7. restore: two devices, one parent ----------------------------------------------------

func _test_restore_two_devices():
	var failures: Array = []
	var clock: Clock = Clock.new()
	# Device A buys.
	var backend_a: FakeBackend = FakeBackend.new()
	backend_a.replies = [[200, _decision_body("active", NOW + 30 * DAY)]]
	var device_a: Dictionary = _rig(backend_a, clock)
	device_a["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
	if not device_a["service"].is_active(EntitlementIds.FAMILY_CLUB):
		return ["device A's purchase did not verify; restore cannot be tested"]
	# Device B shares the store account: the SAME mock gateway instance stands in
	# for "the store remembers the purchase"; a fresh provider stands in for the
	# second install.
	var backend_b: FakeBackend = FakeBackend.new()
	backend_b.replies = [[200, _decision_body("active", NOW + 30 * DAY)]]
	var provider_b: RefCounted = StoreProvider.new(Callable(clock, "read"))
	var verify_b: RefCounted = VerifyClient.new()
	verify_b.configure(Callable(backend_b, "transport"), "device-b")
	var flow_b: RefCounted = PurchaseFlow.new(device_a["gateway"], verify_b, provider_b, Callable(clock, "read"))
	var recorder_b: Recorder = Recorder.new()
	flow_b.connect("flow_finished", recorder_b.on_finished)
	var service_b: RefCounted = EntitlementService.new(provider_b)
	if service_b.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("device B was entitled before restoring")
	flow_b.restore(true)
	if recorder_b.last() != PurchaseFlow.OUTCOME_RESTORED:
		failures.append("restore on device B ended %s" % str(recorder_b.outcomes))
	if backend_b.requests.size() != 1 or String(backend_b.requests[0]["body"]["clientId"]) != "device-b":
		failures.append("restore did not verify device B's receipt once as device-b: %s" % str(backend_b.requests))
	if String(backend_b.requests[0]["body"]["transactionId"]) != "mock-txn-1":
		failures.append("restore forwarded a different transaction than the one bought")
	if not service_b.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("device B is not entitled after a verified restore")
	if flow_b.is_busy():
		failures.append("the flow stayed busy after restore")
	# Nothing to restore on a fresh account.
	var empty: Dictionary = _rig(FakeBackend.new(), clock)
	empty["flow"].restore(true)
	if empty["recorder"].last() != PurchaseFlow.OUTCOME_NOTHING_TO_RESTORE:
		failures.append("an empty restore ended %s" % empty["recorder"].last())
	if empty["service"].is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("an empty restore granted")
	# A restore whose backend is down grants nothing and ends cleanly.
	var down: FakeBackend = FakeBackend.new()
	down.replies = [[503, "{\"ok\":false,\"code\":\"billing_disabled\"}"]]
	var provider_c: RefCounted = StoreProvider.new(Callable(clock, "read"))
	var verify_c: RefCounted = VerifyClient.new()
	verify_c.configure(Callable(down, "transport"), "device-c")
	var flow_c: RefCounted = PurchaseFlow.new(device_a["gateway"], verify_c, provider_c, Callable(clock, "read"))
	var recorder_c: Recorder = Recorder.new()
	flow_c.connect("flow_finished", recorder_c.on_finished)
	flow_c.restore(true)
	if recorder_c.last() != PurchaseFlow.OUTCOME_NOTHING_TO_RESTORE or provider_c.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a restore against a down backend did not end empty-handed: %s" % str(recorder_c.outcomes))
	return failures


# -- 8. gate + busy ------------------------------------------------------------------------

func _test_gate_and_busy_rules():
	var failures: Array = []
	var clock: Clock = Clock.new()
	var backend: FakeBackend = FakeBackend.new()
	backend.replies = [[200, _decision_body("active", NOW + 30 * DAY)]]
	var rig: Dictionary = _rig(backend, clock)
	var closed: Dictionary = rig["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, false)
	if String(closed.get("outcome", "")) != PurchaseFlow.OUTCOME_GATE_CLOSED:
		failures.append("a purchase with the gate closed was not refused: %s" % str(closed))
	if not rig["gateway"].calls.is_empty():
		failures.append("the store was called with the gate closed")
	var closed_restore: Dictionary = rig["flow"].restore(false)
	if String(closed_restore.get("outcome", "")) != PurchaseFlow.OUTCOME_GATE_CLOSED or not rig["gateway"].calls.is_empty():
		failures.append("a restore with the gate closed reached the store")
	# Busy: hold the backend reply, try again, then release.
	backend.hold = true
	rig["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
	if not rig["flow"].is_busy():
		failures.append("the flow is not busy while the backend is thinking")
	var second: Dictionary = rig["flow"].begin_purchase(StoreProducts.FAMILY_YEARLY, true)
	if String(second.get("outcome", "")) != PurchaseFlow.OUTCOME_BUSY:
		failures.append("a second purchase while busy was not refused: %s" % str(second))
	if rig["gateway"].calls.size() != 1:
		failures.append("the busy refusal still reached the store")
	backend.release_all()
	if rig["flow"].is_busy() or rig["recorder"].last() != PurchaseFlow.OUTCOME_VERIFIED:
		failures.append("the held purchase did not complete after release: %s" % str(rig["recorder"].outcomes))
	# Cancelled at the store: no verify, no grant, not busy.
	var rig2: Dictionary = _rig(FakeBackend.new(), clock)
	rig2["gateway"].script_next_purchase(StoreGateway.RECEIPT_CANCELLED)
	rig2["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
	if rig2["recorder"].last() != PurchaseFlow.OUTCOME_CANCELLED or rig2["flow"].is_busy():
		failures.append("a cancelled purchase ended %s" % rig2["recorder"].last())
	if rig2["service"].is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a cancelled purchase granted")
	return failures


# -- 9. failures change nothing ---------------------------------------------------------

func _test_failures_change_nothing():
	var failures: Array = []
	var clock: Clock = Clock.new()
	var backend: FakeBackend = FakeBackend.new()
	backend.replies = [[200, _decision_body("active", NOW + 30 * DAY)]]
	var rig: Dictionary = _rig(backend, clock)
	rig["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
	if not rig["service"].is_active(EntitlementIds.FAMILY_CLUB):
		return ["setup: the first purchase did not verify"]
	for reply: Array in [[500, "boom"], [0, ""], [200, "not json"], [200, "{\"ok\":true}"],
			[200, "{\"ok\":true,\"decision\":{\"entitlementId\":\"familyClub\"}}"],
			[400, "{\"ok\":false,\"code\":\"bad_request\"}"], [409, "{\"ok\":false,\"code\":\"conflict\"}"]]:
		backend.replies = [reply]
		rig["flow"].begin_purchase(StoreProducts.FAMILY_MONTHLY, true)
		if rig["recorder"].last() != PurchaseFlow.OUTCOME_FAILED:
			failures.append("reply %s ended %s, not failed" % [str(reply), rig["recorder"].last()])
		if not rig["service"].is_active(EntitlementIds.FAMILY_CLUB):
			failures.append("reply %s revoked the held decision; a failure must change nothing" % str(reply))
		if rig["flow"].is_busy():
			failures.append("reply %s left the flow busy" % str(reply))
	# A verify client with no transport sends nothing and says so.
	var bare: RefCounted = VerifyClient.new()
	var reasons: Array = []
	bare.connect("verify_failed", func(failure: Dictionary) -> void: reasons.append(failure))
	if bare.verify({"store": "mock", "productId": StoreProducts.FAMILY_MONTHLY, "transactionId": "t", "payload": {}}):
		failures.append("an unconfigured verify client claimed to send")
	if reasons.is_empty() or String(reasons[0].get("code", "")) != VerifyClient.FAIL_BACKEND_UNAVAILABLE:
		failures.append("an unconfigured verify client did not fail as backend_unavailable: %s" % str(reasons))
	if VerifyClient.request_body({"store": "mock", "productId": "x"}, "c").size() != 0:
		failures.append("request_body() built a request from an incomplete receipt")
	return failures


# -- 10. adapters ------------------------------------------------------------------------

func _test_platform_adapters_unavailable():
	var failures: Array = []
	if Engine.has_singleton(AppleGateway.SINGLETON_NAME) or Engine.has_singleton(GoogleGateway.SINGLETON_NAME):
		return ["a store plugin singleton is present in the test run; this case assumes none"]
	for adapter: RefCounted in [AppleGateway.new(), GoogleGateway.new()]:
		var errors: Array = []
		adapter.connect("store_error", func(error: Dictionary) -> void: errors.append(error))
		if adapter.is_available():
			failures.append("%s says it is available with no plugin" % adapter.gateway_id())
		var query: Dictionary = adapter.query_products(StoreProducts.ALL)
		var restore: Dictionary = adapter.restore_purchases()
		if String(query.get("status", "")) != StoreGateway.STATUS_UNAVAILABLE \
				or String(restore.get("status", "")) != StoreGateway.STATUS_UNAVAILABLE:
			failures.append("%s did not report unavailable: %s / %s" % [adapter.gateway_id(), str(query), str(restore)])
		if errors.size() != 2 or String(errors[0].get("code", "")) != StoreGateway.ERROR_STORE_UNAVAILABLE:
			failures.append("%s did not emit store_unavailable for each call: %s" % [adapter.gateway_id(), str(errors)])
		adapter.poll()  # must be a harmless no-op with no plugin
	if String(Factory.for_platform("iOS").gateway_id()) != "apple" \
			or String(Factory.for_platform("Android").gateway_id()) != "google" \
			or String(Factory.for_platform("macOS").gateway_id()) != "mock" \
			or String(Factory.for_platform().gateway_id()) != "mock":
		failures.append("the factory picks the wrong gateway for a platform")
	return failures


# -- 11. the service surface for the parent screen ---------------------------------------------

func _test_service_surface():
	var failures: Array = []
	var service: RefCounted = EntitlementService.new()
	var status: Dictionary = service.subscription_status()
	if String(status.get("status", "")) != "none" or not String(status.get("entitlementId", "x")).is_empty():
		failures.append("the offline service's subscription_status() is %s" % str(status))
	for key: String in ["entitlementId", "status", "periodEnd", "verifiedAt", "source"]:
		if not status.has(key):
			failures.append("subscription_status() lacks '%s'" % key)
	for forbidden: String in ["price", "receipt", "productId", "displayPrice"]:
		if status.has(forbidden) or service.describe().has(forbidden):
			failures.append("the service surface carries '%s'" % forbidden)
	var store_provider: RefCounted = StoreProvider.new()
	if bool(store_provider.billing_available()):
		failures.append("billing_available() is true in a disabled build")
	store_provider.set_gateway_available(true)
	if bool(store_provider.billing_available()):
		failures.append("billing_available() is true with a gateway but purchases disabled")
	if bool(store_provider.trusts_cached_state()):
		failures.append("the store provider trusts the service cache; its own bounded cache is the only one")
	return failures
