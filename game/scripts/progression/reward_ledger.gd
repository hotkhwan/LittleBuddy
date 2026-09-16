class_name RewardLedger
extends RefCounted

## The single place that decides whether a completion may earn stars.
##
## Two things can wrongly hand out stars twice:
##   1. the same completion being reported twice (a signal connected twice, a
##      retry, a scene reload mid-celebration);
##   2. a child hammering the same object -- spam taps.
##
## Both are refused here, before `SaveService.add_stars()` is ever called, so
## the guard cannot be bypassed by a caller that forgets to check. `award()` is
## the only path that grants stars; a refused award returns `granted == 0` and
## leaves the save file untouched.
##
## Pure logic: no autoloads, no nodes. The save object is passed in and only
## needs `add_stars()` (and optionally `get_stars()` /
## `mark_activity_completed()`), so tests can drive it with a fake.
##
## Offline only. No network, no analytics.

signal stars_awarded(completion_id: String, granted: int, total: int)
signal award_refused(completion_id: String, reason: String)

const SELF_PATH: String = "res://scripts/progression/reward_ledger.gd"

const REASON_DUPLICATE: String = "duplicate"
const REASON_TOO_SOON: String = "tooSoon"
const REASON_INVALID: String = "invalid"

## A second award for a *different* completion arriving sooner than this is
## treated as a spam tap. Comfortably shorter than any real interaction, long
## enough to swallow a double-fired input.
const DEFAULT_MIN_INTERVAL_MS: int = 350

## Upper bound on a single award, so a bad content value cannot inflate stars.
const MAX_STARS_PER_AWARD: int = 5

var min_interval_ms: int = DEFAULT_MIN_INTERVAL_MS

## Injectable clock (milliseconds). Tests replace it to drive the spam guard
## deterministically; gameplay uses the engine clock.
var clock: Callable = Callable(Time, "get_ticks_msec")

var _claimed: Dictionary = {}
var _session_stars: int = 0
var _session_completions: int = 0
var _last_award_ms: int = -1_000_000


static func create() -> RefCounted:
	var script: GDScript = load(SELF_PATH) as GDScript
	if script == null:
		return null
	return script.new()


# ---------------------------------------------------------------------------
# Claims
# ---------------------------------------------------------------------------

## Reserves `completion_id`. Returns `true` exactly once per id -- useful when a
## caller wants the guard without granting stars (e.g. a celebration replay).
func claim(completion_id: String) -> bool:
	var key: String = completion_id.strip_edges()
	if key.is_empty() or _claimed.has(key):
		return false
	_claimed[key] = true
	return true


func is_claimed(completion_id: String) -> bool:
	return _claimed.has(completion_id.strip_edges())


func get_claimed_ids() -> Array:
	var ids: Array = []
	for key: Variant in _claimed.keys():
		ids.append(String(key))
	return ids


# ---------------------------------------------------------------------------
# Awarding
# ---------------------------------------------------------------------------

## Grants `stars` for `completion_id`, at most once, and persists via
## `save_service` when one is supplied.
##
## Returns:
##   {
##     "granted": int,          # 0 when refused
##     "previousStars": int,
##     "stars": int,            # total after the award
##     "duplicate": bool,
##     "reason": String,        # "" when granted
##   }
func award(completion_id: String, stars: int = 1, save_service: Object = null) -> Dictionary:
	var key: String = completion_id.strip_edges()
	var previous: int = _read_total(save_service)

	if key.is_empty() or stars <= 0:
		return _refuse(key, REASON_INVALID, previous)

	if _claimed.has(key):
		return _refuse(key, REASON_DUPLICATE, previous)

	var now: int = _now_ms()
	if now - _last_award_ms < maxi(min_interval_ms, 0):
		# Deliberately does NOT claim the id: the child can try again a moment
		# later and still be rewarded. Spam is ignored, not punished.
		return _refuse(key, REASON_TOO_SOON, previous)

	var granted: int = mini(stars, MAX_STARS_PER_AWARD)
	_claimed[key] = true
	_last_award_ms = now
	_session_stars += granted
	_session_completions += 1

	var total: int = previous + granted
	if save_service != null and save_service.has_method("add_stars"):
		total = int(save_service.call("add_stars", granted))
	if save_service != null and save_service.has_method("mark_activity_completed"):
		save_service.call("mark_activity_completed", key)

	stars_awarded.emit(key, granted, total)
	return {
		"granted": granted,
		"previousStars": previous,
		"stars": total,
		"duplicate": false,
		"reason": "",
	}


# ---------------------------------------------------------------------------
# Session bookkeeping (feeds the session summary screen)
# ---------------------------------------------------------------------------

func get_session_stars() -> int:
	return _session_stars


func get_session_completions() -> int:
	return _session_completions


## Starts a fresh play session. Claims are kept by default so a completion that
## already paid out cannot pay out again just because a new session began.
func begin_session(forget_claims: bool = false) -> void:
	_session_stars = 0
	_session_completions = 0
	if forget_claims:
		_claimed.clear()


## Full reset, including the duplicate guard. Only for an explicit new profile.
func reset() -> void:
	_claimed.clear()
	_session_stars = 0
	_session_completions = 0
	_last_award_ms = -1_000_000


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _refuse(key: String, reason: String, previous: int) -> Dictionary:
	award_refused.emit(key, reason)
	return {
		"granted": 0,
		"previousStars": previous,
		"stars": previous,
		"duplicate": reason == REASON_DUPLICATE,
		"reason": reason,
	}


func _read_total(save_service: Object) -> int:
	if save_service != null and save_service.has_method("get_stars"):
		return int(save_service.call("get_stars"))
	return _session_stars


func _now_ms() -> int:
	if clock.is_valid():
		var value: Variant = clock.call()
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			return int(value)
	return 0
