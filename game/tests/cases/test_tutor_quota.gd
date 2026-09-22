extends RefCounted

## TutorQuota: the daily allowance of ACTIVE AI-tutor time, local mirror and
## cloud client, plus the entitlement providers and the grown-up controls that
## read it. Every clock here is injected; nothing sleeps.
##
## Pinned:
##   * 300 s of active ticks exhausts the free day; held seconds do not count;
##   * a "restart" (new instance over the same save) resumes the count;
##   * the UTC day rolling over resets it; a clock wound backwards does not;
##   * `near_end` once per session, at 60 s; `expired` only at a boundary after
##     `request_end_at_boundary()`, once, never mid-turn;
##   * Family Club's allowance comes from `quota_config.json`, via the dev
##     provider, and goes away when revoked;
##   * the store stub never claims a purchase succeeded;
##   * the settings rows persist and "Delete learning history" clears exactly the
##     two tutor keys;
##   * the cloud parser reads the recorded backend fixture and maps every error
##     code to a state; the client itself is refused while the flag is off.

const TutorQuotaScript := preload("res://scripts/tutor/quota/tutor_quota.gd")
const QuotaLedger := preload("res://scripts/tutor/quota/quota_ledger.gd")
const QuotaConfig := preload("res://scripts/tutor/quota/quota_config.gd")
const BackendResponse := preload("res://scripts/tutor/quota/backend_response.gd")
const CloudClientScript := preload("res://scripts/tutor/quota/cloud_quota_client.gd")
const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const EntitlementServiceScript := preload("res://scripts/entitlement/entitlement_service.gd")
const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")
const DevProviderScript := preload("res://scripts/entitlement/dev_entitlement_provider.gd")
const StoreProviderScript := preload("res://scripts/entitlement/store_entitlement_provider.gd")
const ModelScript := preload("res://scripts/parent_settings/parent_settings_model.gd")

const PARENT_SCENE: String = "res://scenes/parent/parent_settings.tscn"
const FIXTURE: String = "res://tests/fixtures/tutor_backend_session.json"

## 2026-09-20T10:00:00Z.
const T0: int = 1789898400


## A save service that behaves like the real one for settings, and remembers
## every key it was asked to write.
class FakeSaveService:
	extends RefCounted
	var settings: Dictionary = {}
	var stars: int = 7
	var writes: Array = []

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		if settings.has(key):
			return settings[key]
		return default_value

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value
		writes.append(key)

	func get_stars() -> int:
		return stars

	func reset_profile() -> void:
		settings.clear()
		stars = 0


## An injectable clock.
class FakeClock:
	extends RefCounted
	var now: int = T0

	func read() -> int:
		return now

	func advance(seconds: int) -> void:
		now += seconds


## A mock "billing" result, TESTS ONLY: what a platform would hand back, so the
## stub can be shown to forward it and claim nothing.
class MockReceipt:
	extends RefCounted
	static func apple() -> Dictionary:
		return {"signedTransaction": "mock.jws.payload", "productId": "little_days.family_club.monthly"}

	static func google_play() -> Dictionary:
		return {"purchaseToken": "mock-token", "productId": "little_days.family_club.monthly",
				"packageName": "com.joinanny.littledays"}


func test_name() -> String:
	return "tutor_quota"


func run():
	var failures: Array = []
	failures.append_array(_test_config())
	failures.append_array(_test_exhaustion_and_holds())
	failures.append_array(_test_restart_does_not_reset())
	failures.append_array(_test_day_rollover_resets())
	failures.append_array(_test_clock_rollback_grants_nothing())
	failures.append_array(_test_near_end_once())
	failures.append_array(_test_expired_only_at_boundary())
	failures.append_array(_test_begin_with_nothing_left())
	failures.append_array(_test_family_club_allowance_and_dev_provider())
	failures.append_array(_test_store_stub_never_claims_success())
	failures.append_array(_test_reset_local_text())
	failures.append_array(_test_settings_model_rows())
	failures.append_array(_test_settings_screen_section())
	failures.append_array(_test_delete_history_clears_only_tutor_keys())
	failures.append_array(_test_backend_fixture_parses())
	failures.append_array(_test_error_codes_map_to_states())
	failures.append_array(_test_cloud_client_refused_while_flag_off())
	failures.append_array(_test_cloud_quota_is_truth_when_applied())
	return failures


func _quota(save: Object, clock: FakeClock, entitlements: Object = null) -> RefCounted:
	return TutorQuotaScript.new(save, entitlements, Callable(clock, "read"))


# -- config -------------------------------------------------------------------

func _test_config():
	var failures: Array = []
	QuotaConfig.reset_cache()
	var config: Dictionary = QuotaConfig.load_config(true)
	if int(config["freeDailySeconds"]) != 300:
		failures.append("freeDailySeconds is %s, expected 300" % str(config["freeDailySeconds"]))
	if int(config["familyClubDailySeconds"]) != 1800:
		failures.append("familyClubDailySeconds is %s, expected 1800" % str(config["familyClubDailySeconds"]))
	if int(config["warnAtSeconds"]) != 60:
		failures.append("warnAtSeconds is %s, expected 60" % str(config["warnAtSeconds"]))
	var pricing: Dictionary = config["pricingProposed"]
	if String(pricing["currency"]) != "THB" or int(pricing["monthly"]) != 99 or String(pricing["status"]) != "proposed":
		failures.append("pricingProposed is %s" % str(pricing))
	# Junk in: bounded defaults out. A zero free allowance is a typo, not a plan.
	var junk: Dictionary = QuotaConfig.sanitise({"freeDailySeconds": 0, "familyClubDailySeconds": "lots",
			"warnAtSeconds": -5, "pricingProposed": {"currency": 12, "monthly": "99"}})
	if int(junk["freeDailySeconds"]) < QuotaConfig.MIN_DAILY_SECONDS:
		failures.append("a zero free allowance was accepted")
	if int(junk["familyClubDailySeconds"]) != QuotaConfig.DEFAULT_FAMILY_CLUB_DAILY_SECONDS:
		failures.append("a non-numeric Family Club allowance was not defaulted")
	if int(junk["warnAtSeconds"]) < 10:
		failures.append("a negative warning threshold was accepted")
	if int(junk["pricingProposed"]["monthly"]) != 0:
		failures.append("a string price was accepted")
	if QuotaConfig.sanitise(null)["freeDailySeconds"] != QuotaConfig.DEFAULT_FREE_DAILY_SECONDS:
		failures.append("a missing config does not give the default allowance")
	if QuotaConfig.daily_allowance_for("family_club") != 1800 or QuotaConfig.daily_allowance_for("free") != 300:
		failures.append("daily_allowance_for() does not follow the config")
	return failures


# -- exhaustion -------------------------------------------------------------

func _test_exhaustion_and_holds():
	var failures: Array = []
	var save := FakeSaveService.new()
	var clock := FakeClock.new()
	var quota: RefCounted = _quota(save, clock)
	var state: Dictionary = quota.state()
	for key: String in ["entitlement", "dailyAllowanceSeconds", "usedSeconds", "remainingSeconds",
			"resetAtUtc", "resetAtLocalText", "sessionActive"]:
		if not state.has(key):
			failures.append("state() lacks the contract key %s" % key)
	if String(state["entitlement"]) != "free":
		failures.append("a fresh quota is not 'free': %s" % str(state))
	if float(state["dailyAllowanceSeconds"]) != 300.0 or float(state["remainingSeconds"]) != 300.0:
		failures.append("a fresh free day is not 300 s: %s" % str(state))
	if bool(state["sessionActive"]):
		failures.append("sessionActive before begin_session()")

	# Ticks before a session count nothing.
	quota.tick(10.0)
	if float(quota.state()["usedSeconds"]) != 0.0:
		failures.append("tick() counted before begin_session()")

	if not quota.begin_session():
		failures.append("begin_session() refused a fresh day")
	if not bool(quota.state()["sessionActive"]):
		failures.append("sessionActive is false after begin_session()")

	# Held seconds are not tutor time (mirrors play_session.gd).
	quota.pause_for("loading")
	quota.tick(30.0)
	quota.resume_for("loading")
	quota.set_held("menu", true)
	quota.tick(30.0)
	quota.set_held("menu", false)
	quota.set_app_active(false)
	quota.tick(30.0)
	quota.set_app_active(true)
	if float(quota.state()["usedSeconds"]) != 0.0:
		failures.append("held / background seconds were counted: %s" % str(quota.state()))

	# 300 one-second ticks: the free day is gone, one second at a time.
	var changed: Array = [0]
	quota.quota_changed.connect(func(_s: Dictionary) -> void: changed[0] += 1)
	for _i: int in range(299):
		quota.tick(1.0)
		clock.advance(1)
	if quota.is_exhausted():
		failures.append("exhausted at 299 s")
	if float(quota.state()["remainingSeconds"]) != 1.0:
		failures.append("after 299 s the remaining is %s" % str(quota.state()["remainingSeconds"]))
	quota.tick(1.0)
	if not quota.is_exhausted():
		failures.append("not exhausted after 300 s of active ticks")
	if float(quota.state()["remainingSeconds"]) != 0.0:
		failures.append("remaining did not reach 0: %s" % str(quota.state()))
	if changed[0] < 250:
		failures.append("quota_changed fired only %d times over 300 s; the screen could not follow" % changed[0])
	# Negative deltas never un-use seconds.
	quota.tick(-100.0)
	if float(quota.state()["usedSeconds"]) < 300.0:
		failures.append("a negative tick un-used seconds")
	# The ledger reached the save (throttled, then flushed on exhaustion).
	if not save.settings.has("tutorQuota"):
		failures.append("nothing was persisted under tutorQuota")
	else:
		var stored: Dictionary = save.settings["tutorQuota"]
		if float(stored.get("usedSeconds", 0.0)) < 300.0:
			failures.append("the persisted ledger says %s, expected >= 300" % str(stored))
		if String(stored.get("dayUtc", "")) != "2026-09-20":
			failures.append("the ledger is keyed by %s, expected the UTC day 2026-09-20" % str(stored.get("dayUtc")))
		if String(stored.get("entitlement", "")) != "free":
			failures.append("the ledger did not record the entitlement")
	# Not a write per tick.
	if save.writes.size() > 80:
		failures.append("the ledger wrote the profile %d times in 300 s; it must throttle" % save.writes.size())
	quota.end_session()
	if bool(quota.state()["sessionActive"]):
		failures.append("sessionActive after end_session()")
	return failures


# -- restart --------------------------------------------------------------

func _test_restart_does_not_reset():
	var failures: Array = []
	var save := FakeSaveService.new()
	var clock := FakeClock.new()
	var first: RefCounted = _quota(save, clock)
	first.begin_session()
	for _i: int in range(120):
		first.tick(1.0)
		clock.advance(1)
	first.end_session()  # the app closes; the ledger is flushed
	var stored_before: Dictionary = (save.settings.get("tutorQuota", {}) as Dictionary).duplicate(true)

	# "Reopen the app": a brand new instance over the same save, a minute later.
	clock.advance(60)
	var second: RefCounted = _quota(save, clock)
	var state: Dictionary = second.state()
	if absf(float(state["usedSeconds"]) - 120.0) > 0.01:
		failures.append("after a restart the used seconds are %s, expected 120 (stored %s)"
				% [str(state["usedSeconds"]), str(stored_before)])
	if absf(float(state["remainingSeconds"]) - 180.0) > 0.01:
		failures.append("after a restart the remaining is %s, expected 180" % str(state["remainingSeconds"]))
	# And it carries on from there.
	second.begin_session()
	for _i: int in range(180):
		second.tick(1.0)
		clock.advance(1)
	if not second.is_exhausted():
		failures.append("120 s before a restart plus 180 s after did not exhaust the 300 s day")

	# A corrupt ledger starts fresh rather than crashing or granting extra.
	save.settings["tutorQuota"] = {"dayUtc": "not a day", "usedSeconds": "many"}
	var third: RefCounted = _quota(save, clock)
	if float(third.state()["remainingSeconds"]) != 300.0:
		failures.append("a corrupt ledger did not start a fresh day: %s" % str(third.state()))
	save.settings["tutorQuota"] = "junk"
	var fourth: RefCounted = _quota(save, clock)
	if float(fourth.state()["remainingSeconds"]) != 300.0:
		failures.append("a non-dictionary ledger did not start a fresh day")
	return failures


# -- rollover --------------------------------------------------------------

func _test_day_rollover_resets():
	var failures: Array = []
	var save := FakeSaveService.new()
	var clock := FakeClock.new()
	var quota: RefCounted = _quota(save, clock)
	quota.begin_session()
	for _i: int in range(300):
		quota.tick(1.0)
		clock.advance(1)
	quota.end_session()
	if not quota.is_exhausted():
		failures.append("setup: not exhausted")
	var state: Dictionary = quota.state()
	if String(state["resetAtUtc"]) != "2026-09-21T00:00:00Z":
		failures.append("resetAtUtc is %s, expected 2026-09-21T00:00:00Z" % str(state["resetAtUtc"]))

	# 23:59:59 UTC the same day: still nothing.
	clock.now = QuotaLedger.day_start_unix("2026-09-21") - 1
	quota.refresh()
	if float(quota.state()["remainingSeconds"]) != 0.0:
		failures.append("time came back before midnight UTC")
	# Midnight UTC: a new day.
	clock.now = QuotaLedger.day_start_unix("2026-09-21")
	quota.refresh()
	state = quota.state()
	if float(state["remainingSeconds"]) != 300.0 or float(state["usedSeconds"]) != 0.0:
		failures.append("the UTC day rolled over but the ledger did not reset: %s" % str(state))
	if String(state["resetAtUtc"]) != "2026-09-22T00:00:00Z":
		failures.append("after rollover resetAtUtc is %s" % str(state["resetAtUtc"]))
	if not quota.begin_session():
		failures.append("begin_session() refused the new day")
	quota.end_session()
	var stored: Dictionary = save.settings.get("tutorQuota", {})
	if String(stored.get("dayUtc", "")) != "2026-09-21":
		failures.append("the persisted ledger did not move to the new day: %s" % str(stored))

	# A restart across midnight (the app was closed at 22:00, reopened at 08:00
	# the next UTC day) also resets.
	var save2 := FakeSaveService.new()
	var clock2 := FakeClock.new()
	var a: RefCounted = _quota(save2, clock2)
	a.begin_session()
	for _i: int in range(300):
		a.tick(1.0)
	a.end_session()
	clock2.advance(20 * 3600)
	var b: RefCounted = _quota(save2, clock2)
	if float(b.state()["remainingSeconds"]) != 300.0:
		failures.append("a restart on the next UTC day did not reset: %s" % str(b.state()))
	return failures


# -- rollback ---------------------------------------------------------------

func _test_clock_rollback_grants_nothing():
	var failures: Array = []
	var save := FakeSaveService.new()
	var clock := FakeClock.new()
	var quota: RefCounted = _quota(save, clock)
	quota.begin_session()
	for _i: int in range(300):
		quota.tick(1.0)
		clock.advance(1)
	quota.end_session()

	# Wind the clock back a day, in the running instance.
	clock.advance(-86400 - 3600)
	quota.refresh()
	if float(quota.state()["remainingSeconds"]) != 0.0:
		failures.append("winding the clock back granted %s s" % str(quota.state()["remainingSeconds"]))
	if quota.begin_session():
		failures.append("begin_session() opened a session on a wound-back clock")

	# And in a fresh instance (restart after the rollback): still nothing.
	var again: RefCounted = _quota(save, clock)
	if float(again.state()["remainingSeconds"]) != 0.0:
		failures.append("a restart on a wound-back clock granted %s s" % str(again.state()["remainingSeconds"]))
	if not again.ledger().clock_is_behind():
		failures.append("the ledger does not know the clock is behind")
	# The reset time does not move backwards either.
	if String(again.state()["resetAtUtc"]) != "2026-09-21T00:00:00Z":
		failures.append("the reset moved to %s after a rollback" % str(again.state()["resetAtUtc"]))

	# Once real time catches up past the stored day's end, the day rolls over.
	clock.now = QuotaLedger.day_start_unix("2026-09-21") + 5
	again.refresh()
	if float(again.state()["remainingSeconds"]) != 300.0:
		failures.append("the day did not roll over once the clock caught up: %s" % str(again.state()))

	# Seconds are never un-used by a hand-edited smaller lastSeenUnix either:
	# usage stands, and the monotonic mark only moves forward.
	var ledger: RefCounted = again.ledger()
	var seen_before: int = ledger.last_seen_unix()
	clock.advance(-10)
	ledger.touch()
	if ledger.last_seen_unix() != seen_before:
		failures.append("lastSeenUnix moved backwards")
	return failures


# -- near_end ---------------------------------------------------------------

func _test_near_end_once():
	var failures: Array = []
	var save := FakeSaveService.new()
	var clock := FakeClock.new()
	var quota: RefCounted = _quota(save, clock)
	var warnings: Array = []
	quota.near_end.connect(func(remaining: float) -> void: warnings.append(remaining))
	quota.begin_session()
	for _i: int in range(239):
		quota.tick(1.0)
	if not warnings.is_empty():
		failures.append("near_end fired at %s s remaining, before 60" % str(warnings))
	quota.tick(1.0)  # 240 used, 60 left
	if warnings.size() != 1 or absf(float(warnings[0]) - 60.0) > 0.01:
		failures.append("near_end at 60 s: got %s" % str(warnings))
	for _i: int in range(70):
		quota.tick(1.0)
	if warnings.size() != 1:
		failures.append("near_end fired %d times in one session; once" % warnings.size())
	quota.end_session()

	# A new session that starts already under the threshold is warned at once,
	# once; a session that starts with plenty is not.
	var save2 := FakeSaveService.new()
	var early: RefCounted = _quota(save2, clock)
	var early_warnings: Array = []
	early.near_end.connect(func(remaining: float) -> void: early_warnings.append(remaining))
	early.begin_session()
	for _i: int in range(250):
		early.tick(1.0)
	early.end_session()
	var resumed: RefCounted = _quota(save2, clock)
	resumed.near_end.connect(func(remaining: float) -> void: early_warnings.append(remaining))
	if early_warnings.size() != 1:
		failures.append("setup: first session warned %d times" % early_warnings.size())
	resumed.begin_session()
	if early_warnings.size() != 2:
		failures.append("a session begun with 50 s left did not warn at once (%d)" % early_warnings.size())
	resumed.tick(5.0)
	if early_warnings.size() != 2:
		failures.append("the resumed session warned again")
	return failures


# -- expired ---------------------------------------------------------------

func _test_expired_only_at_boundary():
	var failures: Array = []
	var save := FakeSaveService.new()
	var clock := FakeClock.new()
	var quota: RefCounted = _quota(save, clock)
	var expired: Array = [0]
	quota.expired.connect(func() -> void: expired[0] += 1)

	# NOT armed: running out is reported, never signalled.
	quota.begin_session()
	for _i: int in range(320):
		quota.tick(1.0)
	if not quota.is_exhausted():
		failures.append("setup: not exhausted")
	if expired[0] != 0:
		failures.append("expired fired from tick(); it may only fire at a boundary")
	if not quota.boundary_reached():
		failures.append("boundary_reached() did not say the session should end")
	if expired[0] != 0:
		failures.append("expired fired at a boundary although the scene never armed it")
	quota.end_session()

	# Armed: silence mid-turn, one signal at the next boundary, then quiet.
	var save2 := FakeSaveService.new()
	var armed: RefCounted = _quota(save2, clock)
	var fired: Array = [0]
	armed.expired.connect(func() -> void: fired[0] += 1)
	armed.begin_session()
	armed.request_end_at_boundary()
	if armed.boundary_reached():
		failures.append("boundary_reached() asked to end with 300 s left")
	for _i: int in range(150):
		armed.tick(1.0)
	if armed.boundary_reached() or fired[0] != 0:
		failures.append("expired / end requested with 150 s left")
	for _i: int in range(170):
		armed.tick(1.0)  # 320 s: over, mid-turn
	if fired[0] != 0:
		failures.append("expired fired mid-turn (from tick) while armed; it must wait for the boundary")
	if not armed.is_exhausted():
		failures.append("setup: armed session not exhausted")
	if not armed.boundary_reached():
		failures.append("boundary_reached() did not end the exhausted armed session")
	if fired[0] != 1:
		failures.append("expired fired %d times at the boundary, expected exactly 1" % fired[0])
	armed.tick(3.0)
	if not armed.boundary_reached() or fired[0] != 1:
		failures.append("a second boundary re-fired expired (%d) or stopped asking to end" % fired[0])
	armed.end_session()
	if armed.boundary_reached():
		failures.append("boundary_reached() asked to end a session that is over")
	# The ledger kept the honest overshoot; the screen clamps at 0.
	if float(save2.settings["tutorQuota"]["usedSeconds"]) < 320.0:
		failures.append("the overshoot past the allowance was not recorded")
	if float(armed.state()["remainingSeconds"]) != 0.0:
		failures.append("remaining went negative")
	return failures


func _test_begin_with_nothing_left():
	var failures: Array = []
	var save := FakeSaveService.new()
	var clock := FakeClock.new()
	var first: RefCounted = _quota(save, clock)
	first.begin_session()
	for _i: int in range(300):
		first.tick(1.0)
	first.end_session()
	var again: RefCounted = _quota(save, clock)
	var fired: Array = [0]
	again.expired.connect(func() -> void: fired[0] += 1)
	again.request_end_at_boundary()
	if again.begin_session():
		failures.append("begin_session() opened a session with 0 s left")
	if fired[0] != 0:
		failures.append("expired fired from begin_session(); nothing started, the scene reads state()")
	if not bool(again.state()["exhausted"]):
		failures.append("state() does not say exhausted")
	if bool(again.state()["sessionActive"]):
		failures.append("a refused session is marked active")
	return failures


# -- Family Club -------------------------------------------------------------

func _test_family_club_allowance_and_dev_provider():
	var failures: Array = []
	var save := FakeSaveService.new()
	var clock := FakeClock.new()
	var dev: RefCounted = DevProviderScript.new()
	var service: RefCounted = EntitlementServiceScript.new(dev)
	var quota: RefCounted = _quota(save, clock, service)

	if service.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the dev provider grants familyClub before being told to")
	if String(quota.state()["entitlement"]) != "free" or float(quota.state()["dailyAllowanceSeconds"]) != 300.0:
		failures.append("before a grant the quota is not the free one: %s" % str(quota.state()))

	if not dev.grant(EntitlementIds.FAMILY_CLUB):
		failures.append("the dev provider refused to grant familyClub")
	if not service.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the service does not see the dev grant")
	if not service.is_active(EntitlementIds.FREE_STARTER):
		failures.append("Free Starter went away under the dev provider")
	var state: Dictionary = quota.state()
	if String(state["entitlement"]) != "family_club":
		failures.append("the quota did not map familyClub -> family_club: %s" % str(state))
	if float(state["dailyAllowanceSeconds"]) != 1800.0 or float(state["remainingSeconds"]) != 1800.0:
		failures.append("Family Club's allowance is not the configured 1800 s: %s" % str(state))
	if float(state["dailyAllowanceSeconds"]) >= 24 * 3600:
		failures.append("Family Club is 'unlimited'; it must be a number")

	# Use 600 s as Family Club: a free day would be long gone.
	quota.begin_session()
	for _i: int in range(600):
		quota.tick(1.0)
	if quota.is_exhausted():
		failures.append("Family Club exhausted after 600 s of an 1800 s day")
	quota.end_session()
	if String(save.settings["tutorQuota"]["entitlement"]) != "family_club":
		failures.append("the ledger did not record family_club")

	# Revoked: back to the free number, and today's 600 s stand against it.
	dev.revoke(EntitlementIds.FAMILY_CLUB)
	if service.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("revoke() did not revoke")
	state = quota.state()
	if String(state["entitlement"]) != "free" or float(state["remainingSeconds"]) != 0.0:
		failures.append("after revoke the quota should be free with 0 s left (600 used): %s" % str(state))
	# The ledger's stored entitlement is a record, never a grant.
	var replay: RefCounted = _quota(save, clock)  # default service: no dev provider
	if String(replay.state()["entitlement"]) != "free":
		failures.append("a stored 'family_club' in the ledger granted Family Club to a fresh service")

	# Unknown ids stay unknown under the dev provider too.
	if dev.grant("everything"):
		failures.append("the dev provider granted an unknown id")
	if dev.is_active("everything"):
		failures.append("the dev provider reports an unknown id active")
	# Without the user arg, nothing hands out a dev provider.
	if DevProviderScript.from_environment() != null and not DevProviderScript.is_enabled_by_args():
		failures.append("from_environment() built a dev provider without the user arg")
	if EntitlementServiceScript.new().is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the default service grants familyClub in a test run")
	return failures


# -- store stub --------------------------------------------------------------

func _test_store_stub_never_claims_success():
	var failures: Array = []
	var store: RefCounted = StoreProviderScript.new()
	if store.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("the store stub grants familyClub")
	if not store.is_active(EntitlementIds.FREE_STARTER):
		failures.append("the store stub withholds Free Starter")
	if bool(store.trusts_cached_state()):
		failures.append("the store stub trusts a cache; fail closed until a real provider bounds it")
	if bool(store.billing_available()):
		failures.append("the store stub says billing is available")
	for platform: String in ["apple", "google_play"]:
		var receipt: Dictionary = MockReceipt.apple() if platform == "apple" else MockReceipt.google_play()
		var verdict: Dictionary = store.validate_purchase(platform, receipt)
		if String(verdict.get("status", "")) != "pending_server_validation":
			failures.append("%s: validate_purchase() answered %s, expected pending_server_validation"
					% [platform, str(verdict.get("status"))])
		if not String(verdict.get("entitlement", "x")).is_empty():
			failures.append("%s: the stub named an entitlement (%s)" % [platform, str(verdict.get("entitlement"))])
		if String(verdict.get("validatedBy", "")) != "server":
			failures.append("%s: the stub does not say the server validates" % platform)
		# Feeding the verdict back changes nothing.
		if store.is_active(EntitlementIds.FAMILY_CLUB):
			failures.append("%s: familyClub became active after a mock receipt" % platform)
	var bad: Dictionary = store.validate_purchase("carrier_pigeon", {"x": 1})
	if String(bad.get("status", "")) != "rejected_locally":
		failures.append("an unknown platform was not rejected: %s" % str(bad))
	var empty: Dictionary = store.validate_purchase("apple", {})
	if String(empty.get("status", "")) != "rejected_locally":
		failures.append("an empty receipt was not rejected: %s" % str(empty))
	# And a service over the stub is still the free service.
	var service: RefCounted = EntitlementServiceScript.new(store)
	if service.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a service over the store stub grants familyClub")
	service.from_dict({"stateVersion": 1, "providerId": "storeStub", "active": ["familyClub"]})
	if service.is_active(EntitlementIds.FAMILY_CLUB):
		failures.append("a hand-written cache granted familyClub through the store stub")
	return failures


# -- local text ---------------------------------------------------------------

func _test_reset_local_text():
	var failures: Array = []
	var clock := FakeClock.new()  # 10:00Z on 2026-09-20
	var quota: RefCounted = _quota(FakeSaveService.new(), clock)
	quota.set_time_zone_bias_minutes(7 * 60)  # Bangkok
	var text: String = String(quota.state()["resetAtLocalText"])
	if text != "Resets at 07:00 tomorrow":
		failures.append("Bangkok reset text is '%s', expected 'Resets at 07:00 tomorrow'" % text)
	quota.set_time_zone_bias_minutes(0)
	text = String(quota.state()["resetAtLocalText"])
	if text != "Resets at 00:00 tomorrow":
		failures.append("UTC reset text is '%s'" % text)
	quota.set_time_zone_bias_minutes(-7 * 60)  # UTC-7: 03:00Z now, reset 17:00 today
	text = String(quota.state()["resetAtLocalText"])
	if text != "Resets at 17:00 today":
		failures.append("UTC-7 reset text is '%s', expected 'Resets at 17:00 today'" % text)
	if TutorQuotaScript.format_clock(300.0) != "5:00" or TutorQuotaScript.format_clock(59.4) != "0:59" \
			or TutorQuotaScript.format_clock(1800.0) != "30:00":
		failures.append("format_clock() is wrong")
	return failures


# -- settings model ---------------------------------------------------------------

func _test_settings_model_rows():
	var failures: Array = []
	var save := FakeSaveService.new()
	var model: RefCounted = ModelScript.new(save)
	if not model.get_ai_tutor_enabled():
		failures.append("aiTutorEnabled must default to true (the local scripted tutor)")
	if save.settings.has("aiTutorEnabled"):
		failures.append("reading the default wrote the key")
	model.set_ai_tutor_enabled(false)
	if save.settings.get("aiTutorEnabled", true) != false:
		failures.append("set_ai_tutor_enabled(false) did not persist: %s" % str(save.settings))
	if ModelScript.KEY_AI_TUTOR_ENABLED != "aiTutorEnabled":
		failures.append("the key must be aiTutorEnabled")
	var reread: RefCounted = ModelScript.new(save)
	if reread.get_ai_tutor_enabled():
		failures.append("the persisted Off was not read back")
	save.settings["aiTutorEnabled"] = "maybe"
	if not reread.get_ai_tutor_enabled():
		failures.append("a corrupt value must fall back to the default")
	# No service: still works from the cache.
	var detached: RefCounted = ModelScript.new(null)
	detached.set_ai_tutor_enabled(false)
	if detached.get_ai_tutor_enabled():
		failures.append("without a service the toggle did not remember its value")
	if ModelScript.KEY_TUTOR_QUOTA != "tutorQuota" or ModelScript.KEY_TUTOR_PROGRESS != "tutorProgress":
		failures.append("the tutor keys the delete clears are misnamed")
	return failures


# -- settings screen ---------------------------------------------------------------

func _test_settings_screen_section():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	var packed: PackedScene = load(PARENT_SCENE) as PackedScene
	var panel: Control = packed.instantiate() as Control
	tree.root.add_child(panel)
	panel.call("_ready")

	if bool(panel.call("is_learn_with_aliz_visible")):
		failures.append("Learn with Aliz is on screen while the gate is locked")
	panel.call("open_settings")
	if not bool(panel.call("is_learn_with_aliz_visible")):
		failures.append("Learn with Aliz is missing from the unlocked panel")

	# Every row is inside the ScrollContainer.
	var scroll: ScrollContainer = panel.find_child("Center", true, false) as ScrollContainer
	for node_name: String in ["LearnWithAlizBox", "AiTutorOnButton", "AiTutorOffButton", "AiTutorCloudLabel",
			"AlizAllowanceValue", "AlizMicrophoneValue", "AlizLanguageEnButton", "AlizLoudnessNote",
			"AlizPrivacyBox", "AlizDeleteHistoryButton", "AlizSubscriptionValue", "AlizPricingLabel",
			"HandsFreeOnButton", "HandsFreeOffButton", "AlizVoiceButtons", "AlizHistoryBox"]:
		var node: Node = panel.find_child(node_name, true, false)
		if node == null:
			failures.append("%s is missing" % node_name)
		elif scroll == null or not scroll.is_ancestor_of(node):
			failures.append("%s is not inside the ScrollContainer" % node_name)

	# Cloud off in this build, said so.
	if TutorFlags.cloud_enabled():
		failures.append("the cloud flag is ON in a test run")
	if String(panel.call("aliz_cloud_text")) != "Cloud tutor: not available in this build.":
		failures.append("the cloud line reads '%s'" % String(panel.call("aliz_cloud_text")))
	# Allowance, read-only, from the meter.
	var allowance: String = String(panel.call("aliz_allowance_text"))
	if not allowance.begins_with("Used 0:00 of 5:00 today") or not allowance.contains("Resets at"):
		failures.append("the allowance row reads '%s'" % allowance)
	# Microphone: no SpeechService in the runner -> Not checked.
	if String(panel.call("aliz_microphone_text")) != "Not checked":
		failures.append("the microphone row reads '%s' with no speech service" % String(panel.call("aliz_microphone_text")))
	# Language: fixed and disabled.
	var language: Button = panel.find_child("AlizLanguageEnButton", true, false) as Button
	if language == null or not language.disabled or language.text != "English" or not language.button_pressed:
		failures.append("the learning language selector is not a disabled, selected 'English'")
	# Subscription and price, from the config, honest about billing.
	if String(panel.call("aliz_subscription_text")) != "Free":
		failures.append("the subscription row reads '%s'" % String(panel.call("aliz_subscription_text")))
	var pricing: String = String(panel.call("aliz_pricing_text"))
	if not pricing.contains("THB 99 / month (proposed)") or not pricing.contains("Billing is not available yet."):
		failures.append("the pricing line reads '%s'" % pricing)
	# Privacy: a static label (no button), link-free, the exact claim the
	# privacy guards keep true, per docs/ALIZ_TUTOR_PARENT_INFO.md.
	if not bool(panel.call("is_aliz_privacy_visible")):
		failures.append("the privacy text is not on screen with the section")
	if panel.find_child("AlizPrivacyButton", true, false) != null:
		failures.append("the privacy information has a button; it must be a static label")
	var privacy: String = " ".join(panel.call("aliz_privacy_lines"))
	for forbidden: String in ["http", "www.", ".com", "learn more"]:
		if privacy.to_lower().contains(forbidden):
			failures.append("the privacy text contains '%s'" % forbidden)
	if not privacy.contains("The online AI tutor is switched off in this build."):
		failures.append("the privacy text lost the sentence the guards depend on")
	for required: String in ["runs on this device", "Nothing is recorded, saved or sent anywhere", "Parent Corner"]:
		if not privacy.contains(required):
			failures.append("the privacy text never says '%s'" % required)
	if privacy.split(" ").size() > 130:
		failures.append("the privacy text is %d words; keep it at or under 120" % privacy.split(" ").size())
	# The toggle persists through the model.
	var off: Button = panel.find_child("AiTutorOffButton", true, false) as Button
	off.button_pressed = true
	off.pressed.emit()
	var model: RefCounted = panel.call("model")
	if model.get_ai_tutor_enabled():
		failures.append("tapping Off did not turn the AI tutor off in the model")
	var on: Button = panel.find_child("AiTutorOnButton", true, false) as Button
	on.button_pressed = true
	on.pressed.emit()
	if not model.get_ai_tutor_enabled():
		failures.append("tapping On did not turn the AI tutor back on")
	# Close collapses privacy and disarms delete; Done / Close still work.
	var delete_button: Button = panel.find_child("AlizDeleteHistoryButton", true, false) as Button
	delete_button.pressed.emit()
	if not bool(panel.call("is_aliz_delete_armed")):
		failures.append("the first tap on Delete learning history did not arm")
	var closed: Array = [0]
	panel.connect("closed", func() -> void: closed[0] += 1)
	panel.call("close_settings")
	if closed[0] != 1 or bool(panel.call("is_panel_visible")):
		failures.append("close_settings() no longer closes")
	if bool(panel.call("is_aliz_delete_armed")):
		failures.append("closing did not disarm delete")
	panel.call("open_settings")
	if bool(panel.call("is_aliz_delete_armed")):
		failures.append("re-opening restored an armed delete")
	var done: Button = panel.find_child("DoneButton", true, false) as Button
	done.pressed.emit()
	if closed[0] != 2:
		failures.append("Done no longer closes")

	tree.root.remove_child(panel)
	panel.free()
	return failures


func _test_delete_history_clears_only_tutor_keys():
	var failures: Array = []
	var save := FakeSaveService.new()
	save.stars = 12
	save.settings = {
		"musicVolume": 0.4, "helperLanguage": "ja", "aiTutorEnabled": false,
		"tutorProgress": {"fruits_1": {"stepIndex": 3, "completed": false}},
		"entitlements": {"stateVersion": 1, "providerId": "localOffline", "active": ["freeStarter"]},
	}
	var clock := FakeClock.new()
	var quota: RefCounted = _quota(save, clock)
	quota.begin_session()
	for _i: int in range(200):
		quota.tick(1.0)
	quota.end_session()
	var before: Dictionary = save.settings.duplicate(true)

	var model: RefCounted = ModelScript.new(save)
	if not model.delete_learning_history():
		failures.append("delete_learning_history() reported no service")
	if not (save.settings.get("tutorProgress", {"x": 1}) as Dictionary).is_empty():
		failures.append("tutorProgress was not cleared: %s" % str(save.settings.get("tutorProgress")))
	var ledger_after: Dictionary = save.settings.get("tutorQuota", {})
	if float(ledger_after.get("usedSeconds", 1.0)) != 0.0:
		failures.append("tutorQuota usage was not cleared: %s" % str(ledger_after))
	# The model's ledger runs on the real clock: it keeps the stored day, or has
	# legitimately rolled over to today's UTC day when the fixture day is past.
	var today_utc: String = Time.get_date_string_from_system(true)
	if String(ledger_after.get("dayUtc", "")) not in ["2026-09-20", today_utc]:
		failures.append("the delete lost the ledger's day (got %s)" % str(ledger_after.get("dayUtc")))
	for key: String in ["musicVolume", "helperLanguage", "aiTutorEnabled", "entitlements"]:
		if save.settings.get(key) != before.get(key):
			failures.append("delete_learning_history() changed %s" % key)
	if save.stars != 12:
		failures.append("delete_learning_history() touched the stars")
	# The meter sees the cleared ledger after a reload.
	var fresh: RefCounted = _quota(save, clock)
	if float(fresh.state()["remainingSeconds"]) != 300.0:
		failures.append("after the delete the meter still shows %s" % str(fresh.state()))

	# Through the real screen: two taps, the same result, stars intact.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var save2 := FakeSaveService.new()
		save2.stars = 5
		save2.settings = {"tutorProgress": {"a": 1}, "tutorQuota": {"dayUtc": "2026-09-20", "usedSeconds": 100.0,
				"entitlement": "free", "lastSeenUnix": T0}, "voiceVolume": 0.5}
		var packed: PackedScene = load(PARENT_SCENE) as PackedScene
		var panel: Control = packed.instantiate() as Control
		tree.root.add_child(panel)
		panel.call("_ready")
		var model2: RefCounted = panel.call("model")
		model2.set_service(save2)
		panel.call("open_settings")
		var button: Button = panel.find_child("AlizDeleteHistoryButton", true, false) as Button
		button.pressed.emit()
		if not (save2.settings["tutorProgress"] as Dictionary).has("a"):
			failures.append("ONE tap deleted the history; it must take a confirming second tap")
		button.pressed.emit()
		if not (save2.settings["tutorProgress"] as Dictionary).is_empty():
			failures.append("two taps did not clear tutorProgress")
		if float((save2.settings["tutorQuota"] as Dictionary).get("usedSeconds", 1.0)) != 0.0:
			failures.append("two taps did not clear today's usage")
		if save2.stars != 5 or float(save2.settings.get("voiceVolume", 0.0)) != 0.5:
			failures.append("the screen's delete touched stars or another setting")
		if bool(panel.call("is_aliz_delete_armed")):
			failures.append("the delete button stayed armed after deleting")
		tree.root.remove_child(panel)
		panel.free()
	return failures


# -- cloud ---------------------------------------------------------------------

func _fixture() -> Dictionary:
	var file: FileAccess = FileAccess.open(FIXTURE, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _exchange(fixture: Dictionary, name: String) -> Dictionary:
	for entry: Variant in fixture.get("exchanges", []):
		if typeof(entry) == TYPE_DICTIONARY and String((entry as Dictionary).get("name", "")) == name:
			return entry
	return {}


func _test_backend_fixture_parses():
	var failures: Array = []
	var fixture: Dictionary = _fixture()
	if fixture.is_empty():
		return ["cannot read %s" % FIXTURE]

	var created: Dictionary = _exchange(fixture, "session_created")
	var parsed: Dictionary = BackendResponse.parse(int(created["status"]), JSON.stringify(created["body"]))
	if not bool(parsed["ok"]) or String(parsed["state"]) != "ok":
		failures.append("session_created parsed as %s" % str(parsed))
	if String(parsed.get("sessionId", "")) != "3d3b93a9-6b1e-4d8f-9a1c-2f6f0c1e7b42":
		failures.append("sessionId not read: %s" % str(parsed))
	var quota: Dictionary = parsed.get("quota", {})
	if String(quota.get("entitlement", "")) != "free" or float(quota.get("dailyAllowanceSeconds", 0)) != 300.0 \
			or float(quota.get("remainingSeconds", 0)) != 300.0 or String(quota.get("resetAtUtc", "")) != "2026-09-21T00:00:00.000Z":
		failures.append("the session quota block was not read: %s" % str(quota))

	var turn: Dictionary = _exchange(fixture, "turn_ok")
	parsed = BackendResponse.parse(int(turn["status"]), turn["body"])
	if not bool(parsed["ok"]) or bool(parsed["endAtBoundary"]):
		failures.append("turn_ok parsed as %s" % str(parsed))
	if String((parsed.get("turn", {}) as Dictionary).get("lessonAction", "")) != "next_question":
		failures.append("the TutorTurn was not carried through")
	quota = parsed.get("quota", {})
	if absf(float(quota.get("usedSeconds", 0)) - 120.5) > 0.001 or absf(float(quota.get("remainingSeconds", 0)) - 179.5) > 0.001:
		failures.append("the turn quota block was not read: %s" % str(quota))
	if int(parsed.get("turnIndex", 0)) != 1 or float(parsed.get("chargedSeconds", 0)) != 12.0:
		failures.append("turnIndex / chargedSeconds not read: %s" % str(parsed))

	var last: Dictionary = _exchange(fixture, "turn_last_of_the_day")
	parsed = BackendResponse.parse(int(last["status"]), last["body"])
	if not bool(parsed["ok"]) or not bool(parsed["endAtBoundary"]):
		failures.append("the last turn's endAtBoundary was not read: %s" % str(parsed))
	if float((parsed.get("quota", {}) as Dictionary).get("remainingSeconds", 1)) != 0.0:
		failures.append("the last turn's remaining is not 0")

	var ended: Dictionary = _exchange(fixture, "session_ended")
	parsed = BackendResponse.parse(int(ended["status"]), ended["body"])
	if not bool(parsed["ok"]) or String(parsed.get("endedAt", "")) != "2026-09-20T15:19:21.676Z":
		failures.append("session_ended parsed as %s" % str(parsed))
	if int((parsed.get("usage", {}) as Dictionary).get("turns", 0)) != 2:
		failures.append("usage totals not carried")

	var entitlement: Dictionary = _exchange(fixture, "entitlement_family_club")
	parsed = BackendResponse.parse(int(entitlement["status"]), entitlement["body"])
	if String(parsed.get("entitlement", "")) != "family_club":
		failures.append("the entitlement reply was not read: %s" % str(parsed))
	quota = parsed.get("quota", {})
	if float(quota.get("dailyAllowanceSeconds", 0)) != 1800.0 or float(quota.get("remainingSeconds", 0)) != 1500.0:
		failures.append("the Family Club quota block was not read: %s" % str(quota))
	if (parsed.get("products", []) as Array).size() != 2:
		failures.append("products not carried (information for a grown-up only)")

	# A server block that disagrees with itself is re-derived, never trusted raw;
	# junk numbers read as 0; "familyClub" (the entitlement-layer id) is accepted.
	var odd: Dictionary = BackendResponse.normalise_quota({"entitlement": "familyClub", "dailyAllowanceSeconds": 1800,
			"usedSeconds": 100, "remainingSeconds": 9999, "resetAtUtc": 5})
	if float(odd["remainingSeconds"]) != 1700.0 or String(odd["entitlement"]) != "family_club" or String(odd["resetAtUtc"]) != "":
		failures.append("normalise_quota() trusted a contradictory block: %s" % str(odd))
	var junk: Dictionary = BackendResponse.normalise_quota({"usedSeconds": "lots", "dailyAllowanceSeconds": -3})
	if float(junk["usedSeconds"]) != 0.0 or float(junk["dailyAllowanceSeconds"]) != 0.0 or float(junk["remainingSeconds"]) != 0.0:
		failures.append("normalise_quota() accepted junk numbers: %s" % str(junk))
	return failures


func _test_error_codes_map_to_states():
	var failures: Array = []
	var fixture: Dictionary = _fixture()
	if fixture.is_empty():
		return ["cannot read %s" % FIXTURE]
	var expected: Dictionary = {
		"error_quota_exhausted": "exhausted",
		"error_not_approved": "needs_parent_approval",
		"error_provider_unavailable": "provider_unavailable",
		"error_rate_limited": "rate_limited",
		"error_timeout": "provider_unavailable",
		"error_session_ended": "session_lost",
		"billing_validate_not_implemented": "client_error",
	}
	for name: String in expected.keys():
		var exchange: Dictionary = _exchange(fixture, name)
		if exchange.is_empty():
			failures.append("the fixture has no exchange '%s'" % name)
			continue
		var parsed: Dictionary = BackendResponse.parse(int(exchange["status"]), JSON.stringify(exchange["body"]))
		if bool(parsed["ok"]):
			failures.append("%s parsed as ok" % name)
		if String(parsed["state"]) != String(expected[name]):
			failures.append("%s mapped to '%s', expected '%s'" % [name, str(parsed["state"]), str(expected[name])])
		if not BackendResponse.is_state(String(parsed["state"])):
			failures.append("%s produced an unknown state" % name)
		var code: String = String((exchange["body"]["error"] as Dictionary)["code"])
		if String(parsed["code"]) != code:
			failures.append("%s lost its code: %s" % [name, str(parsed["code"])])
	# The exhausted reply carries the server's quota block (with the reset time).
	var exhausted: Dictionary = BackendResponse.parse(429, _exchange(fixture, "error_quota_exhausted")["body"])
	if String((exhausted.get("quota", {}) as Dictionary).get("resetAtUtc", "")) != "2026-09-21T00:00:00.000Z":
		failures.append("quota_exhausted did not carry quota.resetAtUtc: %s" % str(exhausted))
	if String(exhausted.get("reason", "")) != "daily_quota":
		failures.append("quota_exhausted lost its reason")
	# rate_limited carries the wait.
	var limited: Dictionary = BackendResponse.parse(429, _exchange(fixture, "error_rate_limited")["body"])
	if float(limited.get("retryAfterSeconds", 0)) != 3.0:
		failures.append("rate_limited lost retryAfterSeconds: %s" % str(limited))
	# No reply at all (timeout on the wire, refused connection): provider_unavailable.
	var silent: Dictionary = BackendResponse.parse(0, "")
	if String(silent["state"]) != "provider_unavailable":
		failures.append("no reply mapped to %s" % str(silent["state"]))
	# A non-JSON 500 and an unknown code on a 5xx: provider_unavailable, never a hang.
	if String(BackendResponse.parse(500, "<html>oops</html>")["state"]) != "provider_unavailable":
		failures.append("a non-JSON 500 did not map to provider_unavailable")
	if BackendResponse.state_for("something_new", 503) != "provider_unavailable":
		failures.append("an unknown code on 503 did not map to provider_unavailable")
	if BackendResponse.state_for("something_new", 400) != "client_error":
		failures.append("an unknown code on 400 did not map to client_error")
	return failures


func _test_cloud_client_refused_while_flag_off():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree"]
	if TutorFlags.cloud_enabled():
		return ["the cloud flag is ON in a test run; nothing below is meaningful"]
	var quota: RefCounted = _quota(FakeSaveService.new(), FakeClock.new())
	if quota.enable_cloud(tree, "test-client", "token"):
		failures.append("enable_cloud() succeeded with the flag off")
	if quota.mode() != "local":
		failures.append("the meter left local mode with the flag off")
	if tree.root.get_node_or_null(NodePath("TutorCloudQuotaClient")) != null:
		failures.append("a cloud client node was created with the flag off")
	var client: Node = CloudClientScript.new()
	if quota.attach_cloud_client(client):
		failures.append("attach_cloud_client() accepted a client with the flag off")
	if quota.mode() != "local":
		failures.append("attaching switched the mode with the flag off")
	# The client itself, out of the tree and unconfigured, fails fast rather than hanging.
	var outcomes: Array = []
	client.request_failed.connect(func(kind: String, parsed: Dictionary) -> void: outcomes.append([kind, parsed]))
	if client.begin_session("fruits_1"):
		failures.append("an unconfigured client claimed to start a request")
	if outcomes.size() != 1 or String((outcomes[0][1] as Dictionary)["state"]) != "provider_unavailable":
		failures.append("an unconfigured client did not fail as provider_unavailable: %s" % str(outcomes))
	client.free()
	return failures


## Cloud replies fed through the client's own finishing path (what a live
## reply takes) into a meter in cloud mode: the server's block is the truth;
## `endAtBoundary` arms exhaustion; `provider_unavailable` drops to local.
func _test_cloud_quota_is_truth_when_applied():
	var failures: Array = []
	var fixture: Dictionary = _fixture()
	var save := FakeSaveService.new()
	var clock := FakeClock.new()
	var quota: RefCounted = _quota(save, clock)

	# With the flag off, apply_server_quota() is informational only.
	quota.apply_server_quota({"entitlement": "family_club", "dailyAllowanceSeconds": 1800, "usedSeconds": 0})
	if String(quota.state()["entitlement"]) != "free" or float(quota.state()["dailyAllowanceSeconds"]) != 300.0:
		failures.append("a server block changed the local meter with the cloud off: %s" % str(quota.state()))

	# Force cloud mode the way attach would (the flag is off, so by the private
	# setter) to test the handling path itself.
	quota.call("_set_mode", "cloud")
	var modes: Array = []
	quota.mode_changed.connect(func(mode: String) -> void: modes.append(mode))
	var unavailable: Array = []
	quota.provider_unavailable.connect(func(reason: String) -> void: unavailable.append(reason))
	var expired: Array = [0]
	quota.expired.connect(func() -> void: expired[0] += 1)

	var client: Node = CloudClientScript.new()
	client.quota_updated.connect(quota._on_server_quota)
	client.request_failed.connect(quota._on_cloud_failed)

	var created: Dictionary = _exchange(fixture, "session_created")
	client.call("_finish", "session", int(created["status"]), JSON.stringify(created["body"]))
	if String(client.session_id()) != "3d3b93a9-6b1e-4d8f-9a1c-2f6f0c1e7b42":
		failures.append("the client did not keep the session id")
	quota.begin_session()
	quota.request_end_at_boundary()
	# Locally tick 200 s; the server has only charged 120.5. The screen shows the server.
	for _i: int in range(200):
		quota.tick(1.0)
	var turn: Dictionary = _exchange(fixture, "turn_ok")
	client.call("_finish", "turn", int(turn["status"]), JSON.stringify(turn["body"]))
	var state: Dictionary = quota.state()
	if absf(float(state["usedSeconds"]) - 120.5) > 0.01 or absf(float(state["remainingSeconds"]) - 179.5) > 0.01:
		failures.append("in cloud mode state() is not the server's block: %s" % str(state))
	if String(state["resetAtUtc"]) != "2026-09-21T00:00:00.000Z":
		failures.append("the server's resetAtUtc was not shown: %s" % str(state["resetAtUtc"]))
	if quota.is_exhausted() or quota.boundary_reached():
		failures.append("the meter ended the session although the server had 179.5 s left")
	# The local ledger mirrored in the background (for a fallback mid-lesson).
	if absf(quota.ledger().used_seconds() - 200.0) > 0.01:
		failures.append("the local mirror stopped counting in cloud mode: %s" % str(quota.ledger().used_seconds()))

	# The last turn: endAtBoundary -> exhausted, expired only at the boundary.
	var last: Dictionary = _exchange(fixture, "turn_last_of_the_day")
	client.call("_finish", "turn", int(last["status"]), JSON.stringify(last["body"]))
	if not quota.is_exhausted():
		failures.append("endAtBoundary: true did not mark the meter exhausted")
	if expired[0] != 0:
		failures.append("expired fired on the server reply, not at the boundary")
	if not quota.boundary_reached() or expired[0] != 1:
		failures.append("the boundary after endAtBoundary did not end the session once (%d)" % expired[0])
	quota.end_session()

	# A 503 mid-lesson: provider_unavailable, and the meter is local again.
	quota.begin_session()
	var outage: Dictionary = _exchange(fixture, "error_provider_unavailable")
	client.call("_finish", "turn", int(outage["status"]), JSON.stringify(outage["body"]))
	if unavailable.size() != 1 or String(unavailable[0]) != "provider_unavailable":
		failures.append("a 503 did not emit provider_unavailable: %s" % str(unavailable))
	if quota.mode() != "local" or modes != ["local"]:
		failures.append("a 503 did not drop the meter to local mode: %s / %s" % [quota.mode(), str(modes)])
	if quota.cloud_client() != null:
		failures.append("the meter kept its cloud client after falling back")
	# Local mode now shows the mirror, which kept the whole day's count.
	if float(quota.state()["remainingSeconds"]) != 0.0:
		failures.append("after the fallback the local mirror shows %s" % str(quota.state()))
	# A quota_exhausted error reply is honoured as the server's word.
	var quota2: RefCounted = _quota(FakeSaveService.new(), clock)
	quota2.call("_set_mode", "cloud")
	quota2.begin_session()
	quota2.apply_server_failure(BackendResponse.parse(429, _exchange(fixture, "error_quota_exhausted")["body"]))
	if not quota2.is_exhausted() or float(quota2.state()["remainingSeconds"]) != 0.0:
		failures.append("quota_exhausted from the server was not honoured: %s" % str(quota2.state()))
	# A lost session (409) does not fall back and does not exhaust.
	client.call("_finish", "turn", 409, JSON.stringify(_exchange(fixture, "error_session_ended")["body"]))
	if not client.session_id().is_empty():
		failures.append("the client kept a session the server says has ended")
	client.free()
	return failures
