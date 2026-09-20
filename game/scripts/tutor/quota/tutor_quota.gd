extends RefCounted
## TutorQuota -- the daily allowance of ACTIVE AI-tutor time, per the contract
## in docs/ALIZ_TUTOR_CONTRACTS.md. The game stays free; the tutor's minutes are
## the one metered thing, and this is the meter the tutor scene talks to.
##
##   var quota := TutorQuotaScript.new(save_service)      # local mirror
##   quota.near_end.connect(...)                          # 60 s left, once
##   quota.expired.connect(...)                           # only at a boundary
##   if quota.begin_session():                            # false = nothing left today
##       quota.request_end_at_boundary()                  # arm: end me when I run out
##       ... each frame: quota.tick(active_delta)
##       ... after each tutor turn: if quota.boundary_reached(): show break screen
##       quota.end_session()
##
## ## Two modes
##
## * **LOCAL MIRROR** (`TutorFlags.cloud_enabled()` false -- every public build):
##   `quota_ledger.gd` counts the seconds the scene reports as active, keyed by
##   UTC day, persisted under the SaveService settings key `tutorQuota`,
##   restart-proof and rollback-proof. This is the only count the offline
##   scripted tutor has.
## * **CLOUD** (flag on, developer runs): `cloud_quota_client.gd` talks to the
##   backend and the server's `quota` block is THE truth -- `state()` shows it
##   verbatim, the local ledger keeps mirroring in the background so a fallback
##   mid-lesson has a sane number, and the client is never trusted for minutes
##   remaining. Any transport failure emits `provider_unavailable` and drops the
##   meter back to local mode; the lesson continues with the scripted tutor.
##
## ## The boundary handshake (why `expired` never fires mid-sentence)
##
## Running out of time must never cut Aliz off mid-turn or yank a child out of
## a question. So the meter never ends a session on its own clock:
##
##   1. The scene ARMS it: `request_end_at_boundary()`, normally right after a
##      successful `begin_session()` (or on `near_end`, if it prefers to decide
##      then). Unarmed, the meter only reports.
##   2. The meter keeps counting. When `remainingSeconds` reaches 0 (locally, or
##      because the server said `endAtBoundary: true` / `quota_exhausted`) it
##      flips `is_exhausted()` and flushes the ledger -- and emits NOTHING yet.
##   3. At the end of every tutor turn (Aliz finished speaking, the child's answer
##      was handled) the scene calls `boundary_reached()`. It returns true when
##      the session should end now; and if the meter was armed, `expired` is
##      emitted here, exactly once per session. The scene then shows the break
##      screen ("Great job today!") and calls `end_session()`.
##
## `begin_session()` returning false is the "nothing left today" case: no
## `expired` is emitted (nothing started), the scene reads `state()` and shows
## the break screen straight away.
##
## `near_end(remainingSeconds)` fires once per session when the remaining time
## first drops to `warnAtSeconds` (60 s from `quota_config.json`) -- also
## immediately on `begin_session()` if the day starts that low -- so the scene
## can steer the lesson towards a natural close.
##
## ## What counts as active (mirrors `play_session.gd`)
##
## `tick(delta)` counts only while a session is open and nothing holds the
## meter: `pause_for("reason")` / `resume_for("reason")` (counted, nested loads
## balance), `set_held("menu", true/false)` (level-triggered), and
## `set_app_active(false)` for the app in the background. Held seconds are not
## tutor time. The scene owns those calls; this object is not a Node and sees no
## notifications itself.
##
## PURE GDScript. No 3D types, no network in this file (the cloud client is a
## separate Node that this object only creates when the flag is on).

const TutorFlags := preload("res://scripts/tutor/tutor_flags.gd")
const QuotaConfig := preload("res://scripts/tutor/quota/quota_config.gd")
const QuotaLedger := preload("res://scripts/tutor/quota/quota_ledger.gd")
const BackendResponse := preload("res://scripts/tutor/quota/backend_response.gd")
const CloudClientScript := preload("res://scripts/tutor/quota/cloud_quota_client.gd")
const EntitlementServiceScript := preload("res://scripts/entitlement/entitlement_service.gd")
const EntitlementIds := preload("res://scripts/entitlement/entitlement_ids.gd")

## The state changed in a way worth redrawing (a whole second, a mode, a session).
signal quota_changed(state: Dictionary)
## Once per session, the first time remaining time is at or under the warning.
signal near_end(remaining_seconds: float)
## Once per session, only from `boundary_reached()`, only when armed.
signal expired()
## The cloud tutor could not be reached or failed; the meter is now local.
signal provider_unavailable(reason: String)
## "local" | "cloud".
signal mode_changed(mode: String)

const MODE_LOCAL: String = "local"
const MODE_CLOUD: String = "cloud"
const CLOUD_CLIENT_NODE_NAME: String = "TutorCloudQuotaClient"

var _ledger: QuotaLedger = null
var _entitlements: Object = null
var _mode: String = MODE_LOCAL
var _cloud: Node = null
var _server_quota: Dictionary = {}
var _session_active: bool = false
var _session_active_seconds: float = 0.0
var _end_requested: bool = false
var _exhausted: bool = false
var _warned: bool = false
var _expired_emitted: bool = false
var _holds: Dictionary = {}
var _app_active: bool = true
var _last_emitted_second: int = -1
## Minutes east of UTC for `resetAtLocalText`; null = the device's zone.
var _time_zone_bias_minutes: Variant = null
## Cloud mode: the lesson the next `begin_session()` opens on the server.
var _pending_lesson_id: String = ""


## `save_service`: the SaveService autoload or any `get_setting`/`set_setting`
## object (null = memory only). `entitlement_service`: anything answering
## `is_active(id)`; null builds the default provider-neutral service. `clock`: a
## Callable returning unix seconds, for tests.
func _init(save_service: Object = null, entitlement_service: Object = null, clock: Callable = Callable()) -> void:
	_ledger = QuotaLedger.new(save_service, clock)
	_entitlements = entitlement_service if entitlement_service != null else EntitlementServiceScript.new()


# -- contract ----------------------------------------------------------------------

## Re-reads the clock (day rollover), the entitlement and -- in cloud mode with
## an idle client -- asks the server for the current entitlement + quota.
func refresh() -> void:
	_ledger.touch()
	if _mode == MODE_CLOUD and _cloud != null and _cloud.has_method("fetch_entitlement") \
			and not bool(_cloud.call("is_busy")):
		_cloud.call("fetch_entitlement")
	_evaluate(true)


## The contract's state block, plus `mode` and `warnAtSeconds` for the screens.
func state() -> Dictionary:
	var entitlement: String = entitlement_name()
	var allowance: float = float(QuotaConfig.daily_allowance_for(entitlement))
	var used: float = _ledger.used_seconds()
	var reset_utc: String = _ledger.reset_at_utc()
	var reset_unix: int = _ledger.reset_at_unix()
	if _mode == MODE_CLOUD and not _server_quota.is_empty():
		entitlement = String(_server_quota.get("entitlement", entitlement))
		allowance = float(_server_quota.get("dailyAllowanceSeconds", allowance))
		used = float(_server_quota.get("usedSeconds", used))
		var server_reset: String = String(_server_quota.get("resetAtUtc", ""))
		if not server_reset.is_empty():
			reset_utc = server_reset
			reset_unix = _unix_from_iso(server_reset, reset_unix)
	var remaining: float = maxf(allowance - used, 0.0)
	return {
		"entitlement": entitlement,
		"dailyAllowanceSeconds": allowance,
		"usedSeconds": snappedf(used, 0.01),
		"remainingSeconds": snappedf(remaining, 0.01),
		"resetAtUtc": reset_utc,
		"resetAtLocalText": reset_at_local_text(reset_unix),
		"sessionActive": _session_active,
		"mode": _mode,
		"warnAtSeconds": QuotaConfig.warn_at_seconds(),
		"exhausted": _exhausted or remaining <= 0.0,
	}


## Opens a session. False when nothing is left today (no signal; the scene
## shows the break screen from `state()`).
func begin_session() -> bool:
	_ledger.touch()
	_session_active_seconds = 0.0
	_end_requested = false
	_expired_emitted = false
	_warned = false
	_exhausted = false
	var remaining: float = float(state()["remainingSeconds"])
	if remaining <= 0.0:
		_exhausted = true
		_session_active = false
		_emit_changed()
		return false
	_session_active = true
	_ledger.record(0.0, entitlement_name())
	if _mode == MODE_CLOUD and _cloud != null and _cloud.has_method("begin_session"):
		_cloud.call("begin_session", _pending_lesson_id)
	_evaluate(true)
	return true


## Cloud mode needs a lesson id for the server; the local mirror ignores it.
func set_lesson_id(lesson_id: String) -> void:
	_pending_lesson_id = lesson_id


## `active_delta` seconds of wall time the scene considers ACTIVE tutor time.
## Ignored while no session is open or the meter is held.
func tick(active_delta: float) -> void:
	var delta: float = maxf(active_delta, 0.0)
	if not _session_active or delta <= 0.0 or not is_counting():
		return
	_session_active_seconds += delta
	_ledger.record(delta, entitlement_name())
	_evaluate(false)


## Closes the session, flushes the ledger, tells the server (cloud mode).
func end_session(reason: String = "") -> void:
	if not _session_active:
		_ledger.flush()
		return
	_session_active = false
	_ledger.flush()
	if _mode == MODE_CLOUD and _cloud != null and _cloud.has_method("end_session"):
		_cloud.call("end_session", reason)
	_emit_changed()


## Arms the meter: when time runs out, `expired` will be emitted at the next
## `boundary_reached()`. Idempotent.
func request_end_at_boundary() -> void:
	_end_requested = true


## The scene calls this at the end of every tutor turn. Returns true when the
## session should end now. Emits `expired` (once) only if armed.
func boundary_reached() -> bool:
	if not _session_active:
		return false
	_evaluate(false)
	if not _exhausted:
		return false
	if _end_requested and not _expired_emitted:
		_expired_emitted = true
		expired.emit()
	return true


# -- holds (mirrors play_session.gd) -----------------------------------------------------

func pause_for(reason: String) -> void:
	var key: String = reason if not reason.is_empty() else "hold"
	_holds[key] = int(_holds.get(key, 0)) + 1


func resume_for(reason: String) -> void:
	var key: String = reason if not reason.is_empty() else "hold"
	if not _holds.has(key):
		return
	var left: int = int(_holds[key]) - 1
	if left <= 0:
		_holds.erase(key)
	else:
		_holds[key] = left


func set_held(reason: String, held: bool) -> void:
	var key: String = reason if not reason.is_empty() else "hold"
	if held:
		_holds[key] = 1
	else:
		_holds.erase(key)


func is_held(reason: String = "") -> bool:
	if reason.is_empty():
		return not _holds.is_empty()
	return _holds.has(reason)


## The app in the background / without focus: not tutor time.
func set_app_active(active: bool) -> void:
	_app_active = active


func is_counting() -> bool:
	return _session_active and _app_active and _holds.is_empty()


# -- reads ------------------------------------------------------------------------------

func mode() -> String:
	return _mode


func is_session_active() -> bool:
	return _session_active


func is_exhausted() -> bool:
	return _exhausted


func is_end_requested() -> bool:
	return _end_requested


func session_active_seconds() -> float:
	return _session_active_seconds


func ledger() -> QuotaLedger:
	return _ledger


## "family_club" when the entitlement service says `familyClub` is active, else
## "free". Asked every time; never read back from the ledger.
func entitlement_name() -> String:
	if _entitlements != null and _entitlements.has_method("is_active") \
			and bool(_entitlements.call("is_active", EntitlementIds.FAMILY_CLUB)):
		return QuotaConfig.ENTITLEMENT_FAMILY_CLUB
	return QuotaConfig.ENTITLEMENT_FREE


func set_entitlement_service(service: Object) -> void:
	_entitlements = service
	_evaluate(true)


func entitlement_service() -> Object:
	return _entitlements


## "Resets at 07:00 tomorrow" in the device's zone (or the injected one).
func reset_at_local_text(reset_unix: int = -1) -> String:
	var at: int = reset_unix if reset_unix >= 0 else _ledger.reset_at_unix()
	var bias_minutes: int = _bias_minutes()
	var local_reset: Dictionary = Time.get_datetime_dict_from_unix_time(at + bias_minutes * 60)
	var local_now: Dictionary = Time.get_datetime_dict_from_unix_time(_ledger.now_unix() + bias_minutes * 60)
	var day_word: String
	var reset_day: int = _ordinal_day(local_reset)
	var now_day: int = _ordinal_day(local_now)
	if reset_day == now_day:
		day_word = "today"
	elif reset_day == now_day + 1:
		day_word = "tomorrow"
	else:
		day_word = "on %04d-%02d-%02d" % [int(local_reset["year"]), int(local_reset["month"]), int(local_reset["day"])]
	return "Resets at %02d:%02d %s" % [int(local_reset["hour"]), int(local_reset["minute"]), day_word]


## Tests: pin the zone. null restores the device's.
func set_time_zone_bias_minutes(bias: Variant) -> void:
	_time_zone_bias_minutes = bias


## "m:ss" for the grown-up screen, e.g. 300 -> "5:00".
static func format_clock(seconds: float) -> String:
	var whole: int = int(floor(maxf(seconds, 0.0)))
	return "%d:%02d" % [whole / 60, whole % 60]


# -- cloud ------------------------------------------------------------------------------

## Switches to cloud mode. Refused (returns false, stays local) while
## `TutorFlags.cloud_enabled()` is false: no public build can reach this path.
## Parks one `CloudQuotaClient` under the tree root and configures it.
func enable_cloud(tree: SceneTree, client_id: String, approval_token: String = "") -> bool:
	if not TutorFlags.cloud_enabled():
		return false
	if tree == null or tree.root == null:
		return false
	var client: Node = tree.root.get_node_or_null(NodePath(CLOUD_CLIENT_NODE_NAME))
	if client == null:
		client = CloudClientScript.new()
		client.name = CLOUD_CLIENT_NODE_NAME
		tree.root.add_child(client)
	client.call("configure", TutorFlags.backend_url(), client_id, approval_token)
	attach_cloud_client(client)
	return true


## Listens to an already-built client (the tutor scene's own, or a test's).
## Still flag-gated: with the cloud off the client is ignored and the meter
## stays local.
func attach_cloud_client(client: Node) -> bool:
	if client == null or not TutorFlags.cloud_enabled():
		return false
	if _cloud != null and _cloud != client:
		_disconnect_cloud()
	_cloud = client
	if client.has_signal("quota_updated") and not client.is_connected("quota_updated", _on_server_quota):
		client.connect("quota_updated", _on_server_quota)
	if client.has_signal("request_failed") and not client.is_connected("request_failed", _on_cloud_failed):
		client.connect("request_failed", _on_cloud_failed)
	_set_mode(MODE_CLOUD)
	return true


## The server's `quota` block, as truth. Public so a conversation provider that
## already talks to the backend can feed the blocks it receives straight in.
func apply_server_quota(quota: Dictionary, end_at_boundary: bool = false) -> void:
	_server_quota = BackendResponse.normalise_quota(quota)
	if _mode != MODE_CLOUD:
		# Not in cloud mode: informational only, never authoritative.
		return
	# The mirror never shows more time than the server granted.
	_ledger.raise_used_to(float(_server_quota.get("usedSeconds", 0.0)))
	if end_at_boundary or float(_server_quota.get("remainingSeconds", 0.0)) <= 0.0:
		_exhausted = true
		_ledger.flush()
	_evaluate(true)


## A backend failure already mapped by `BackendResponse`. `exhausted` is honoured
## as the server's word; `provider_unavailable` (and a lost session with no
## way back) drops the meter to local.
func apply_server_failure(parsed: Dictionary) -> void:
	var state_name: String = String(parsed.get("state", BackendResponse.STATE_PROVIDER_UNAVAILABLE))
	if parsed.has("quota"):
		_server_quota = BackendResponse.normalise_quota(parsed["quota"])
		if _mode == MODE_CLOUD:
			_ledger.raise_used_to(float(_server_quota.get("usedSeconds", 0.0)))
	match state_name:
		BackendResponse.STATE_EXHAUSTED:
			_exhausted = true
			_ledger.flush()
			_evaluate(true)
		BackendResponse.STATE_PROVIDER_UNAVAILABLE:
			_fall_back_to_local(String(parsed.get("code", state_name)))
		_:
			_evaluate(true)


func server_quota() -> Dictionary:
	return _server_quota.duplicate(true)


func cloud_client() -> Node:
	return _cloud


func _on_server_quota(quota: Dictionary, end_at_boundary: bool) -> void:
	apply_server_quota(quota, end_at_boundary)


func _on_cloud_failed(_kind: String, parsed: Dictionary) -> void:
	apply_server_failure(parsed)


func _fall_back_to_local(reason: String) -> void:
	_disconnect_cloud()
	_set_mode(MODE_LOCAL)
	provider_unavailable.emit(reason)
	_evaluate(true)


func _disconnect_cloud() -> void:
	if _cloud == null:
		return
	if _cloud.has_signal("quota_updated") and _cloud.is_connected("quota_updated", _on_server_quota):
		_cloud.disconnect("quota_updated", _on_server_quota)
	if _cloud.has_signal("request_failed") and _cloud.is_connected("request_failed", _on_cloud_failed):
		_cloud.disconnect("request_failed", _on_cloud_failed)
	if _cloud.has_method("cancel"):
		_cloud.call("cancel")
	_cloud = null


func _set_mode(new_mode: String) -> void:
	if _mode == new_mode:
		return
	_mode = new_mode
	mode_changed.emit(_mode)


# -- internals ------------------------------------------------------------------------

## Checks the warning and the exhaustion, emits `quota_changed` when a whole
## second (or anything structural) changed.
func _evaluate(force_emit: bool) -> void:
	var snapshot: Dictionary = state()
	var remaining: float = float(snapshot["remainingSeconds"])
	if _session_active:
		if not _warned and remaining <= float(QuotaConfig.warn_at_seconds()):
			_warned = true
			near_end.emit(remaining)
		if not _exhausted and remaining <= 0.0:
			_exhausted = true
			_ledger.flush()
			force_emit = true
	var second: int = int(floor(remaining))
	if force_emit or second != _last_emitted_second:
		_last_emitted_second = second
		quota_changed.emit(snapshot)


func _emit_changed() -> void:
	_evaluate(true)


func _bias_minutes() -> int:
	if _time_zone_bias_minutes != null and (typeof(_time_zone_bias_minutes) == TYPE_INT or typeof(_time_zone_bias_minutes) == TYPE_FLOAT):
		return int(_time_zone_bias_minutes)
	return int(Time.get_time_zone_from_system().get("bias", 0))


static func _ordinal_day(local: Dictionary) -> int:
	# Days since a fixed epoch, from the calendar fields; good enough to say
	# "today" / "tomorrow" across a month or year boundary.
	var y: int = int(local.get("year", 1970))
	var m: int = int(local.get("month", 1))
	var d: int = int(local.get("day", 1))
	if m <= 2:
		y -= 1
		m += 12
	return 365 * y + y / 4 - y / 100 + y / 400 + (153 * (m - 3) + 2) / 5 + d


static func _unix_from_iso(iso: String, fallback: int) -> int:
	var text: String = iso.strip_edges().trim_suffix("Z")
	var dot: int = text.find(".")
	if dot >= 0:
		text = text.left(dot)
	if text.length() < 19:
		return fallback
	return int(Time.get_unix_time_from_datetime_string(text))
