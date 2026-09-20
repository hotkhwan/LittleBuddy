extends RefCounted

## The LOCAL quota mirror for the scripted tutor: 300 s of active lesson time
## per UTC day, persisted under the settings key `tutorLocalQuota` and
## restart-proof. It is the offline stand-in for Agent F's `TutorQuota`
## (`scripts/tutor/quota/tutor_quota.gd`); `tutor_scene.gd` uses that class when
## the file exists and this one otherwise, through the same surface:
##
##   refresh(), state(), tick(delta), request_end_at_boundary(),
##   signals quota_changed(state), near_end(remainingSeconds), expired
##
## Rules (contract "TutorQuota"): `expired` fires ONLY at a boundary the scene
## has asked for, never mid-turn; `near_end` fires once at 60 s. Storage is
## `{"utcDate": "YYYY-MM-DD", "usedSeconds": float}`; a new UTC day resets it;
## a missing or corrupt value is a fresh day. The save service is duck-typed
## (`get_setting` / `set_setting` / `save_profile`), so a test can hand it a
## dictionary-backed stand-in.

signal quota_changed(state: Dictionary)
signal near_end(remaining_seconds: float)
signal expired()

const SETTING_KEY: String = "tutorLocalQuota"
const DAILY_ALLOWANCE_SECONDS: float = 300.0
const NEAR_END_SECONDS: float = 60.0
## How often the running counter is written back, so a crash loses at most this.
const PERSIST_EVERY_SECONDS: float = 5.0

var _save: Object = null
var _date: String = ""
var _used: float = 0.0
var _session_active: bool = false
var _near_end_sent: bool = false
var _end_requested: bool = false
var _since_persist: float = 0.0
var _allowance: float = DAILY_ALLOWANCE_SECONDS
## A test seam: the "now" the UTC date is read from. Empty means the clock.
var _date_override: String = ""


func _init(save_service: Object = null, allowance_seconds: float = DAILY_ALLOWANCE_SECONDS) -> void:
	_save = save_service
	_allowance = allowance_seconds
	refresh()


func set_save_service(save_service: Object) -> void:
	_save = save_service
	refresh()


func set_date_override(utc_date: String) -> void:
	_date_override = utc_date
	refresh()


## Re-reads the persisted counter, rolling over on a new UTC day.
func refresh() -> void:
	var today: String = utc_date()
	var stored: Variant = null
	if _save != null and _save.has_method("get_setting"):
		stored = _save.call("get_setting", SETTING_KEY, null)
	if typeof(stored) == TYPE_DICTIONARY and String((stored as Dictionary).get("utcDate", "")) == today:
		_used = maxf(float((stored as Dictionary).get("usedSeconds", 0.0)), 0.0)
	else:
		_used = 0.0
	_date = today
	_near_end_sent = remaining_seconds() <= NEAR_END_SECONDS
	quota_changed.emit(state())


func state() -> Dictionary:
	return {
		"entitlement": "free",
		"dailyAllowanceSeconds": _allowance,
		"usedSeconds": _used,
		"remainingSeconds": remaining_seconds(),
		"resetAtUtc": "%sT00:00:00Z" % next_utc_date(),
		"resetAtLocalText": "tomorrow",
		"sessionActive": _session_active,
	}


func remaining_seconds() -> float:
	return maxf(_allowance - _used, 0.0)


func is_exhausted() -> bool:
	return remaining_seconds() <= 0.0


func used_seconds() -> float:
	return _used


func begin_session() -> void:
	refresh()
	_session_active = true
	_end_requested = false


func end_session() -> void:
	_session_active = false
	persist()


## Counts `delta` seconds of ACTIVE lesson time (not the break card, not the
## exit confirm). Emits `near_end` once and `expired` at the next requested
## boundary once the allowance is gone.
func tick(delta: float) -> void:
	if not _session_active or delta <= 0.0:
		return
	if utc_date() != _date:
		refresh()
	_used += delta
	_since_persist += delta
	if _since_persist >= PERSIST_EVERY_SECONDS:
		persist()
	var remaining: float = remaining_seconds()
	if not _near_end_sent and remaining <= NEAR_END_SECONDS:
		_near_end_sent = true
		near_end.emit(remaining)
	if _end_requested and remaining <= 0.0:
		_fire_expired()


## The scene calls this at a safe turn boundary. `expired` fires now if the
## allowance is already gone, otherwise on the tick that exhausts it.
func request_end_at_boundary() -> void:
	_end_requested = true
	if _session_active and is_exhausted():
		_fire_expired()


func persist() -> void:
	_since_persist = 0.0
	if _save == null or not _save.has_method("set_setting"):
		return
	_save.call("set_setting", SETTING_KEY, {"utcDate": _date, "usedSeconds": snappedf(_used, 0.1)})
	if _save.has_method("save_profile"):
		_save.call("save_profile")


func _fire_expired() -> void:
	_end_requested = false
	persist()
	expired.emit()


func utc_date() -> String:
	if not _date_override.is_empty():
		return _date_override
	var now: Dictionary = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(now["year"]), int(now["month"]), int(now["day"])]


func next_utc_date() -> String:
	var unix: int = Time.get_unix_time_from_datetime_string(utc_date() + "T00:00:00") + 86400
	var next: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [int(next["year"]), int(next["month"]), int(next["day"])]
