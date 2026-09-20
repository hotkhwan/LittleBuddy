extends RefCounted
## The LOCAL MIRROR of the daily AI-tutor allowance: a UTC-day-keyed ledger of
## the seconds the tutor scene reported as ACTIVE, persisted through the
## SaveService `settings` block under the key `tutorQuota`.
##
##   {"dayUtc": "2026-09-20", "usedSeconds": 123.5, "entitlement": "free",
##    "lastSeenUnix": 1789990000}
##
## It is a mirror, not an authority: when the cloud tutor is enabled the server
## owns the number and this ledger is not consulted for it. For the offline
## scripted tutor it is the only count there is, so it has three jobs:
##
##   * **Restart-proof.** Every `record()` updates the in-memory ledger and the
##     profile is written at most every `PERSIST_EVERY_SECONDS` of use plus on
##     `flush()`; closing and reopening the app resumes today's count.
##   * **UTC day window.** The count resets when the UTC date changes -- shown to
##     the grown-up in local time by `TutorQuota.state().resetAtLocalText`.
##   * **A clock set backwards grants nothing.** `lastSeenUnix` only ever moves
##     forward; a "new day" is recognised only when now is past the stored day's
##     end AND not before the last moment already seen. Winding the device clock
##     back to yesterday keeps today's ledger, and seconds are never "un-used".
##     (A clock set FORWARD is a new day. Only the server can tell the two apart;
##     that is one reason the server is the authority when the cloud is on.)
##
## The stored `entitlement` is a RECORD of what applied when the seconds were
## used, for the grown-up screen; it is never read to decide the allowance --
## the entitlement service is asked every time.
##
## PURE. No nodes, no network, no 3D. The save service is duck-typed
## (`get_setting`/`set_setting`), the clock is injectable, so a test can run a
## week in a millisecond.

const QuotaConfig := preload("res://scripts/tutor/quota/quota_config.gd")

const SETTING_KEY: String = "tutorQuota"
const SECONDS_PER_DAY: int = 86400
## A crash loses at most this many seconds of usage. `set_setting()` writes the
## profile to disk, so this is also how often the ledger touches storage.
const PERSIST_EVERY_SECONDS: float = 5.0

const FIELD_DAY: String = "dayUtc"
const FIELD_USED: String = "usedSeconds"
const FIELD_ENTITLEMENT: String = "entitlement"
const FIELD_LAST_SEEN: String = "lastSeenUnix"

var _save: Object = null
var _clock: Callable = Callable()
var _day_utc: String = ""
var _used_seconds: float = 0.0
var _entitlement: String = QuotaConfig.ENTITLEMENT_FREE
var _last_seen_unix: int = 0
var _unsaved_seconds: float = 0.0
var _dirty: bool = false


## `save_service`: the SaveService autoload or anything with
## `get_setting`/`set_setting`; null keeps the ledger in memory only.
## `clock`: a Callable returning unix seconds (int); null uses the system clock.
func _init(save_service: Object = null, clock: Callable = Callable()) -> void:
	_save = save_service
	_clock = clock
	load_from_save()


# -- time -----------------------------------------------------------------------

func now_unix() -> int:
	if _clock.is_valid():
		return int(_clock.call())
	return int(Time.get_unix_time_from_system())


## "YYYY-MM-DD" in UTC for a unix time.
static func day_of(unix: int) -> String:
	return Time.get_date_string_from_unix_time(maxi(unix, 0))


## Unix time of 00:00:00 UTC on a "YYYY-MM-DD" day; 0 for junk.
static func day_start_unix(day: String) -> int:
	if not looks_like_day(day):
		return 0
	# Godot parses "YYYY-MM-DDTHH:MM:SS" as UTC.
	return int(Time.get_unix_time_from_datetime_string(day + "T00:00:00"))


## "YYYY-MM-DD", digits in the right places, a plausible month and day.
static func looks_like_day(day: String) -> bool:
	if day.length() != 10 or day[4] != "-" or day[7] != "-":
		return false
	for index: int in [0, 1, 2, 3, 5, 6, 8, 9]:
		var character: String = day[index]
		if character < "0" or character > "9":
			return false
	var month: int = int(day.substr(5, 2))
	var day_of_month: int = int(day.substr(8, 2))
	return month >= 1 and month <= 12 and day_of_month >= 1 and day_of_month <= 31


# -- persistence ---------------------------------------------------------------

## Reads the ledger from the save service; anything malformed starts fresh
## TODAY (fresh = zero used, which is the only safe default for a corrupt file:
## a child is not charged for a broken write, and a fresh ledger still cannot
## exceed today's allowance).
func load_from_save() -> void:
	var raw: Variant = null
	if _save != null and _save.has_method("get_setting"):
		raw = _save.call("get_setting", SETTING_KEY, null)
	from_dict(raw)


## Accepts a stored ledger. Returns true when the stored day was kept.
func from_dict(raw: Variant) -> bool:
	var now: int = now_unix()
	_day_utc = day_of(now)
	_used_seconds = 0.0
	_entitlement = QuotaConfig.ENTITLEMENT_FREE
	_last_seen_unix = now
	_unsaved_seconds = 0.0
	_dirty = false
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var source: Dictionary = raw
	var day: Variant = source.get(FIELD_DAY, "")
	if typeof(day) != TYPE_STRING or day_start_unix(String(day)) <= 0:
		return false
	var used: Variant = source.get(FIELD_USED, 0.0)
	if typeof(used) != TYPE_FLOAT and typeof(used) != TYPE_INT:
		return false
	var seen: Variant = source.get(FIELD_LAST_SEEN, 0)
	var last_seen: int = int(seen) if (typeof(seen) == TYPE_INT or typeof(seen) == TYPE_FLOAT) else 0

	_day_utc = String(day)
	_used_seconds = maxf(float(used), 0.0)
	var stored_entitlement: Variant = source.get(FIELD_ENTITLEMENT, QuotaConfig.ENTITLEMENT_FREE)
	if typeof(stored_entitlement) == TYPE_STRING \
			and String(stored_entitlement) in [QuotaConfig.ENTITLEMENT_FREE, QuotaConfig.ENTITLEMENT_FAMILY_CLUB]:
		_entitlement = String(stored_entitlement)
	# The monotonic mark never moves backwards, not even by loading.
	_last_seen_unix = maxi(last_seen, 0)
	_roll_over_if_due(now)
	return true


func to_dict() -> Dictionary:
	return {
		FIELD_DAY: _day_utc,
		FIELD_USED: snappedf(_used_seconds, 0.01),
		FIELD_ENTITLEMENT: _entitlement,
		FIELD_LAST_SEEN: _last_seen_unix,
	}


## Writes the ledger now, if anything changed. Called on session end, on
## exhaustion and every `PERSIST_EVERY_SECONDS` of use.
func flush() -> bool:
	if not _dirty:
		return false
	_dirty = false
	_unsaved_seconds = 0.0
	if _save == null or not _save.has_method("set_setting"):
		return false
	_save.call("set_setting", SETTING_KEY, to_dict())
	return true


# -- the count ------------------------------------------------------------------

## Adds ACTIVE seconds. Negative deltas are ignored: seconds are never un-used.
## Also the moment the day may roll over (before the add, so the first second of
## a new day lands in the new day).
func record(active_delta: float, entitlement: String = "") -> void:
	var now: int = now_unix()
	touch(now)
	if not entitlement.is_empty():
		_entitlement = entitlement
	var delta: float = maxf(active_delta, 0.0)
	if delta <= 0.0:
		return
	_used_seconds += delta
	_unsaved_seconds += delta
	_dirty = true
	if _unsaved_seconds >= PERSIST_EVERY_SECONDS:
		flush()


## Moves the monotonic mark forward and rolls the day over when due. Safe to
## call as often as you like; a test calls it to "let time pass".
func touch(now: int = -1) -> void:
	var at: int = now if now >= 0 else now_unix()
	_roll_over_if_due(at)
	if at > _last_seen_unix:
		_last_seen_unix = at
		_dirty = true


## A new day starts only when the clock is past the stored day's end AND has
## not been wound back before a moment already seen. Both, or nothing changes.
func _roll_over_if_due(now: int) -> void:
	if now < _last_seen_unix:
		return  # the clock went backwards: keep today's ledger, grant nothing
	if now < reset_at_unix():
		return
	_day_utc = day_of(now)
	_used_seconds = 0.0
	_unsaved_seconds = 0.0
	_dirty = true


## Unix time at which today's ledger resets: the next UTC midnight.
func reset_at_unix() -> int:
	return day_start_unix(_day_utc) + SECONDS_PER_DAY


## ISO-8601 UTC, matching the backend's `resetAtUtc`.
func reset_at_utc() -> String:
	return Time.get_datetime_string_from_unix_time(reset_at_unix(), false) + "Z"


func day_utc() -> String:
	return _day_utc


func used_seconds() -> float:
	return _used_seconds


func entitlement() -> String:
	return _entitlement


func last_seen_unix() -> int:
	return _last_seen_unix


## True when the clock now reads earlier than the latest moment recorded.
func clock_is_behind() -> bool:
	return now_unix() < _last_seen_unix


## The server said more was used than the mirror counted (cloud mode): the
## mirror catches up so a fallback mid-lesson can never show more time than the
## server granted. Never lowers the count.
func raise_used_to(server_used_seconds: float) -> void:
	var target: float = maxf(server_used_seconds, 0.0)
	if target <= _used_seconds:
		return
	_used_seconds = target
	_dirty = true
	flush()


## A grown-up's "Delete learning history": today's count goes back to zero.
## Behind the parental gate only; `lastSeenUnix` is kept so the rollback rule
## still holds afterwards.
func clear_usage() -> void:
	_used_seconds = 0.0
	_unsaved_seconds = 0.0
	_dirty = true
	flush()
