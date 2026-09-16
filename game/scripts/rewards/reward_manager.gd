extends Node
class_name RewardManager

## The ONLY thing in the game that writes stars to `SaveService`.
##
## ## Why this exists at all
##
## Two independent systems can report "the child earned a star":
##
##   1. the legacy `FeedActivity` loop (`%MilkBottle` tap/drag -> `feedMilk`), and
##   2. `MissionRunner`, whose task list also contains `feedMilk`.
##
## `MissionRunner` deliberately never touches `SaveService`, so if both systems
## were live at once the same physical child action would be paid for twice.
## Everything therefore funnels through here, and this class funnels through a
## single process-wide `RewardLedger`.
##
## ## Idempotency
##
## This class adds NO duplicate guard of its own -- a second guard would be a
## second source of truth. It routes every award through `RewardLedger`
## (`res://scripts/progression/reward_ledger.gd`), which refuses an id it has
## already paid for and refuses spam taps inside its 350 ms window.
##
## The ledger is held in a `static var`, so exactly ONE ledger exists for the
## whole run: reloading the Baby Room, or having several `RewardManager`s alive
## at once, still shares one duplicate guard. A per-instance ledger would reset
## the guard on every scene load, which is precisely the bug this prevents.
##
## ## Completion ids and "rounds"
##
## A ledger id may pay out exactly once, ever -- but a child must be able to
## earn `feedMilk` again next time they play. Both facts are reconciled with a
## *round*: `begin_round()` is called once per mission start and once per legacy
## feeding cycle, and completion ids are `"r<round>.<taskId>"`.
##
## Inside one round a task id can pay exactly once, no matter which system
## reports it -- so even if the legacy loop and a mission were (wrongly) live
## together, `feedMilk` could still only be paid for once. The round counter is
## static too, so a scene reload cannot rewind it into ids the ledger has
## already burned.
##
## `completedActivities` in the save file records the BARE task id (`feedMilk`),
## not the round-scoped ledger key, so the profile stays a small, meaningful
## list rather than growing by one entry per round.
##
## SaveService is looked up defensively, so this keeps working in scene previews
## and tests where the autoload does not exist.

## Emitted after every award attempt with the current star total, so a star
## counter stays correct whether the award was granted or refused.
signal star_awarded(total: int)
## Emitted ONLY when stars were actually granted. Celebrate on this one.
signal award_granted(completion_id: String, stars: int, previous_total: int, total: int)
## Emitted when the ledger refused (duplicate / spam tap / invalid).
signal award_refused(completion_id: String, reason: String)

const REWARD_LEDGER_SCRIPT_PATH: String = "res://scripts/progression/reward_ledger.gd"
const SAVE_SERVICE_PATH: String = "/root/SaveService"

const REASON_NO_LEDGER: String = "noLedger"

## The single process-wide duplicate guard. See the class docs above.
static var _shared_ledger: RefCounted = null

## Shared with the ledger: ids must stay unique across scene reloads.
static var _round: int = 0


## The one ledger every `RewardManager` awards through. Created on first use.
static func shared_ledger() -> RefCounted:
	if _shared_ledger == null:
		var script: GDScript = load(REWARD_LEDGER_SCRIPT_PATH) as GDScript
		if script != null:
			_shared_ledger = script.new()
	return _shared_ledger


## Replaces the shared ledger. For tests and for an explicit profile reset --
## gameplay code should never need this.
static func set_shared_ledger(ledger: RefCounted) -> void:
	_shared_ledger = ledger


## Opens a new scoring round (one mission, or one legacy feeding cycle) so the
## same task ids can be earned again without ever reusing a ledger key.
static func begin_round() -> int:
	_round += 1
	return _round


static func get_round() -> int:
	return _round


## The ledger key for `task_id` in the current round. `""` for an empty task id.
static func completion_id(task_id: String) -> String:
	var clean: String = task_id.strip_edges()
	if clean.is_empty():
		return ""
	return "r%d.%s" % [_round, clean]


## -- Instance API ---------------------------------------------------------------

var _save_adapter: SaveAdapter = SaveAdapter.new()
var _explicit_save: Object = null


func get_ledger() -> RefCounted:
	return shared_ledger()


## Pins the persistence backend instead of looking up the `SaveService`
## autoload. For tests and previews; gameplay leaves this unset.
func set_save_service(save_service: Object) -> void:
	_explicit_save = save_service


func _resolve_save_service() -> Object:
	if _explicit_save != null:
		return _explicit_save
	return get_node_or_null(SAVE_SERVICE_PATH)


## Awards `stars` for `task_id` in the current round and returns the new star
## total. A duplicate (or spam tap) returns the unchanged total and writes
## nothing.
func award(task_id: String, stars: int = 1) -> int:
	return int(award_detailed(task_id, stars).get("stars", 0))


## The full ledger result: `{granted, previousStars, stars, duplicate, reason}`.
func award_detailed(task_id: String, stars: int = 1) -> Dictionary:
	var key: String = completion_id(task_id)
	var ledger: RefCounted = get_ledger()

	if ledger == null or not ledger.has_method("award"):
		# The duplicate guard is missing, so paying out would risk paying twice.
		# Refusing is the safe failure: the child keeps playing, nothing is lost
		# except one star, and the save file cannot be corrupted.
		push_warning("RewardManager: no RewardLedger available; refusing to award '%s'" % task_id)
		var total: int = get_stars()
		award_refused.emit(key, REASON_NO_LEDGER)
		star_awarded.emit(total)
		return {
			"granted": 0,
			"previousStars": total,
			"stars": total,
			"duplicate": false,
			"reason": REASON_NO_LEDGER,
		}

	_save_adapter.save_service = _resolve_save_service()
	_save_adapter.activity_id = task_id.strip_edges()

	var result: Dictionary = ledger.call("award", key, stars, _save_adapter)
	var granted: int = int(result.get("granted", 0))
	var new_total: int = int(result.get("stars", 0))

	if granted > 0:
		award_granted.emit(key, granted, int(result.get("previousStars", 0)), new_total)
	else:
		award_refused.emit(key, String(result.get("reason", "")))

	star_awarded.emit(new_total)
	return result


## Convenience read of the current star total; returns 0 if unavailable.
func get_stars() -> int:
	var save_service: Object = _resolve_save_service()
	if save_service != null and save_service.has_method("get_stars"):
		return int(save_service.call("get_stars"))
	return _save_adapter.fallback_total


## -- Save adapter ------------------------------------------------------------------

## Thin shim handed to `RewardLedger.award()`.
##
## It exists for one reason: the ledger marks the completion it was given, which
## is the round-scoped key (`r7.feedMilk`). Writing that into the profile's
## `completedActivities` would make the list grow forever and make
## `is_activity_completed("feedMilk")` false. This maps it back to the bare task
## id before it reaches `SaveService`.
##
## It also keeps an in-memory star total so the reward path still behaves
## sensibly (and the star counter still counts up) when `SaveService` is absent,
## e.g. in a scene preview.
class SaveAdapter extends RefCounted:
	var save_service: Object = null
	var activity_id: String = ""
	var fallback_total: int = 0

	func get_stars() -> int:
		if save_service != null and save_service.has_method("get_stars"):
			return int(save_service.call("get_stars"))
		return fallback_total

	func add_stars(amount: int) -> int:
		if save_service != null and save_service.has_method("add_stars"):
			return int(save_service.call("add_stars", amount))
		fallback_total = maxi(fallback_total + amount, 0)
		return fallback_total

	func mark_activity_completed(_completion_id: String) -> void:
		if activity_id.is_empty():
			return
		if save_service != null and save_service.has_method("mark_activity_completed"):
			save_service.call("mark_activity_completed", activity_id)
