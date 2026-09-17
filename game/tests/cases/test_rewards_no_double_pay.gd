extends RefCounted

## `feedMilk` can never be paid for twice.
##
## It is the one task that exists in BOTH reward systems: the legacy
## `FeedActivity` loop (`%MilkBottle` -> `activity_completed("feedMilk")`) and
## the mission task list (`feedingTime` and `morningRoutine` both contain it).
## If those two ever ran at once, one child action would bank two stars.
##
## `baby_room.gd` prevents that structurally -- mission mode hides and disables
## the legacy bottle and never starts `FeedActivity`. This case proves the
## second, independent line of defence: every star in the game goes through one
## process-wide `RewardLedger` via `RewardManager`, so even if both systems were
## somehow live together the ledger would refuse the second payment.
##
## What is asserted here:
##   1. two separate `RewardManager`s share ONE ledger (a scene reload, or a
##      second manager, must not reset the duplicate guard);
##   2. the legacy loop and a mission reporting `feedMilk` in the same round pay
##      exactly once, in either order;
##   3. a real mission driven end to end pays exactly once per task, and the
##      totals match `MissionRunner.expected_stars()`;
##   4. `feedMilk` in a *later* round still pays, so replaying is still
##      rewarding -- the guard must not turn into a permanent lockout.

const RewardManagerScript := preload("res://scripts/rewards/reward_manager.gd")
const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")
const MissionRunnerScript := preload("res://scripts/gameplay/mission_runner.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")

const LEGACY_TASK_ID: String = "feedMilk"


## Stand-in for the `SaveService` autoload (absent under `--script`). Counts
## calls, so a double payment shows up as a wrong total AND a wrong call count.
class FakeSave extends RefCounted:
	var stars: int = 0
	var add_calls: int = 0
	var completed: Array = []

	func get_stars() -> int:
		return stars

	func add_stars(amount: int) -> int:
		add_calls += 1
		stars = maxi(stars + amount, 0)
		return stars

	func mark_activity_completed(activity_id: String) -> void:
		if not completed.has(activity_id):
			completed.append(activity_id)

	func is_activity_completed(activity_id: String) -> bool:
		return completed.has(activity_id)


## Hand-driven clock, so the ledger's 350 ms spam window is deterministic and a
## synchronous test run is not mistaken for a child hammering the screen.
class FakeClock extends RefCounted:
	var now_ms: int = 500_000

	func advance(ms: int) -> void:
		now_ms += ms

	func read() -> int:
		return now_ms


## Collects every award a `RewardManager` grants, so "exactly once" is checked
## against what the reward path actually emitted, not just the star total.
class AwardLog extends RefCounted:
	var granted: Array = []
	var refused: Array = []

	func on_granted(completion_id: String, stars: int, _previous: int, _total: int) -> void:
		granted.append({"id": completion_id, "stars": stars})

	func on_refused(completion_id: String, reason: String) -> void:
		refused.append({"id": completion_id, "reason": reason})

	func count_for(completion_id: String) -> int:
		var total: int = 0
		for entry: Variant in granted:
			if String((entry as Dictionary).get("id", "")) == completion_id:
				total += 1
		return total


var _clock: FakeClock = null
var _managers: Array = []


func test_name() -> String:
	return "rewards_no_double_pay"


func run():
	var failures: Array = []

	# The shared ledger is a process-wide static, so install a test one with a
	# controllable clock and put it back afterwards.
	var previous_ledger: RefCounted = RewardManagerScript.shared_ledger()
	_clock = FakeClock.new()
	var ledger: RefCounted = RewardLedgerScript.new()
	ledger.clock = Callable(_clock, "read")
	RewardManagerScript.set_shared_ledger(ledger)

	failures.append_array(_test_managers_share_one_ledger())
	failures.append_array(_test_legacy_then_mission())
	failures.append_array(_test_mission_then_legacy())
	failures.append_array(_test_full_mission_pays_once_per_task())
	failures.append_array(_test_next_round_pays_again())

	RewardManagerScript.set_shared_ledger(previous_ledger)
	_free_managers()

	return failures


# ---------------------------------------------------------------------------
# 1. One ledger for the whole run
# ---------------------------------------------------------------------------

func _test_managers_share_one_ledger() -> Array:
	var failures: Array = []

	var a: Node = _manager(FakeSave.new())
	var b: Node = _manager(FakeSave.new())

	if a.get_ledger() != b.get_ledger():
		failures.append("two RewardManagers hold different ledgers; the duplicate guard would reset on a scene reload")
	if a.get_ledger() == null:
		failures.append("RewardManager could not obtain a RewardLedger")

	return failures


# ---------------------------------------------------------------------------
# 2 + 3. feedMilk reported by both systems in one round
# ---------------------------------------------------------------------------

func _test_legacy_then_mission() -> Array:
	return _assert_single_payment("legacy first", true)


func _test_mission_then_legacy() -> Array:
	return _assert_single_payment("mission first", false)


## Reports `feedMilk` from both reward paths inside one round, in both orders.
## Each manager stands for one of the two live systems, and they deliberately
## share a save, exactly as they would in the running game.
func _assert_single_payment(label: String, legacy_first: bool) -> Array:
	var failures: Array = []

	var save: FakeSave = FakeSave.new()
	var legacy_log: AwardLog = AwardLog.new()
	var mission_log: AwardLog = AwardLog.new()
	var legacy: Node = _manager(save, legacy_log)
	var mission: Node = _manager(save, mission_log)

	var round_id: int = RewardManagerScript.begin_round()
	var expected_key: String = "r%d.%s" % [round_id, LEGACY_TASK_ID]

	var first: Node = legacy if legacy_first else mission
	var second: Node = mission if legacy_first else legacy

	_clock.advance(5_000)
	var first_result: Dictionary = first.award_detailed(LEGACY_TASK_ID, 1)
	_clock.advance(5_000)
	var second_result: Dictionary = second.award_detailed(LEGACY_TASK_ID, 1)

	if int(first_result.get("granted", -1)) != 1:
		failures.append("%s: the first feedMilk report granted %s stars, expected 1"
				% [label, str(first_result.get("granted"))])
	if int(second_result.get("granted", -1)) != 0:
		failures.append("%s: feedMilk PAID TWICE -- the second report granted %s stars"
				% [label, str(second_result.get("granted"))])
	if not bool(second_result.get("duplicate", false)):
		failures.append("%s: the second feedMilk report was not refused as a duplicate (reason '%s')"
				% [label, str(second_result.get("reason", ""))])

	if save.stars != 1:
		failures.append("%s: the save holds %d stars after one feeding, expected 1" % [label, save.stars])
	if save.add_calls != 1:
		failures.append("%s: add_stars() was called %d times for one feeding, expected 1"
				% [label, save.add_calls])
	if not save.completed.has(LEGACY_TASK_ID):
		failures.append("%s: the save recorded %s, expected the bare activity id 'feedMilk'"
				% [label, str(save.completed)])

	var total_granted: int = legacy_log.count_for(expected_key) + mission_log.count_for(expected_key)
	if total_granted != 1:
		failures.append("%s: award_granted fired %d times for '%s', expected 1"
				% [label, total_granted, expected_key])

	return failures


# ---------------------------------------------------------------------------
# 4. A whole mission, driven task by task
# ---------------------------------------------------------------------------

## Plays `feedingTime` (which contains `feedMilk`) end to end through the real
## `MissionRunner` and the real content, completing each task by touch, then
## tries to claim `feedMilk` again from the legacy path.
func _test_full_mission_pays_once_per_task() -> Array:
	var failures: Array = []

	var library: Object = ContentLibraryScript.new()
	library.load_all()

	var mission_id: String = "feedingTime"
	var tasks: Array = library.get_mission_tasks(mission_id)
	if tasks.is_empty():
		return ["mission '%s' resolved to no tasks; the content is missing" % mission_id]

	var playable: Array = []
	for task: Variant in tasks:
		if String(MissionRunnerScript.describe_unplayable(task, library)).is_empty():
			playable.append(task)
	if playable.is_empty():
		return ["mission '%s' has no playable tasks" % mission_id]

	var save: FakeSave = FakeSave.new()
	var log: AwardLog = AwardLog.new()
	var manager: Node = _manager(save, log)

	RewardManagerScript.begin_round()

	# Outside a SceneTree `MissionRunner._delay()` runs its callback immediately,
	# so the whole mission plays through synchronously here.
	var runner: Node = MissionRunnerScript.new()
	runner.set_seed(4242)
	var completed_ids: Array = []
	runner.task_completed.connect(func(task_id: String, stars: int) -> void:
		completed_ids.append(task_id)
		# Real play always leaves more than the ledger's 350 ms spam window
		# between two tasks (MissionRunner waits 1.6 s); this reproduces that.
		_clock.advance(2_000)
		manager.award(task_id, stars))

	var finished: Array = []
	runner.mission_completed.connect(func(id: String, stars: int) -> void:
		finished.append({"id": id, "stars": stars}))

	runner.start_mission(mission_id, library, {})

	var guard: int = 0
	while runner.is_running() and guard < 64:
		guard += 1
		var task: Dictionary = runner.get_current_task()
		if task.is_empty():
			break
		# The guaranteed touch path every mode supports.
		runner.on_object_chosen(String(task.get("objectId", "")))

	if runner.is_running():
		failures.append("the mission never finished after %d task completions -- a dead end" % guard)
	if finished.is_empty():
		failures.append("mission_completed never fired")

	var expected_stars: int = MissionRunnerScript.expected_stars(playable)
	if save.stars != expected_stars:
		failures.append("a full '%s' banked %d stars, expected %d"
				% [mission_id, save.stars, expected_stars])
	if save.add_calls != playable.size():
		failures.append("add_stars() was called %d times for %d tasks"
				% [save.add_calls, playable.size()])

	# Every task paid exactly once.
	var seen: Dictionary = {}
	for task_id: Variant in completed_ids:
		var key: String = String(task_id)
		if seen.has(key):
			failures.append("task '%s' completed twice inside one mission" % key)
		seen[key] = true
	if not seen.has(LEGACY_TASK_ID):
		failures.append("mission '%s' did not include '%s'; this case no longer covers the overlap"
				% [mission_id, LEGACY_TASK_ID])

	# ...and now the legacy loop tries to claim the same feeding in the same
	# round. This is the double-pay bug, and it must be refused.
	_clock.advance(2_000)
	var legacy_save: FakeSave = save
	var legacy_manager: Node = _manager(legacy_save)
	var legacy_result: Dictionary = legacy_manager.award_detailed(LEGACY_TASK_ID, 1)
	if int(legacy_result.get("granted", -1)) != 0:
		failures.append("the legacy loop paid for 'feedMilk' AGAIN after the mission already did")
	if save.stars != expected_stars:
		failures.append("the legacy loop changed the total to %d after the mission banked %d"
				% [save.stars, expected_stars])

	runner.free()
	return failures


# ---------------------------------------------------------------------------
# 5. A new round is still rewarding
# ---------------------------------------------------------------------------

func _test_next_round_pays_again() -> Array:
	var failures: Array = []

	var save: FakeSave = FakeSave.new()
	var manager: Node = _manager(save)

	RewardManagerScript.begin_round()
	_clock.advance(5_000)
	manager.award(LEGACY_TASK_ID, 1)

	RewardManagerScript.begin_round()
	_clock.advance(5_000)
	var replay: Dictionary = manager.award_detailed(LEGACY_TASK_ID, 1)

	if int(replay.get("granted", -1)) != 1:
		failures.append("'feedMilk' could not be earned again in a new round (reason '%s'); the guard became a lockout"
				% str(replay.get("reason", "")))
	if save.stars != 2:
		failures.append("two rounds of feedMilk banked %d stars, expected 2" % save.stars)

	return failures


# ---------------------------------------------------------------------------

func _manager(save: Object, log: AwardLog = null) -> Node:
	var manager: Node = RewardManagerScript.new()
	manager.set_save_service(save)
	if log != null:
		manager.award_granted.connect(Callable(log, "on_granted"))
		manager.award_refused.connect(Callable(log, "on_refused"))
	_managers.append(manager)
	return manager


func _free_managers() -> void:
	for manager: Variant in _managers:
		if manager is Node and is_instance_valid(manager):
			(manager as Node).free()
	_managers = []
