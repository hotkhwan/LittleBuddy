extends RefCounted
## Guards a cross-file timing invariant that is easy to break silently.
##
## `RewardLedger` refuses ANY award landing within `min_interval_ms` of the
## previous one -- a global wall-clock spam guard, not a per-id one. That is
## deliberate: a caller that mints a fresh completion id per tap (so the
## duplicate guard cannot help) is still stopped from farming stars.
##
## The cost is that two DIFFERENT, legitimately-earned tasks completing inside
## that window would silently lose the second star -- the child would still see
## "Great!" and a filled progress dot, but no star. Today that is unreachable
## because `MissionRunner` waits `TASK_GAP_SEC` between one task's award and the
## next task even starting.
##
## Nothing enforces that relationship, so shortening TASK_GAP_SEC (or adding a
## mode that completes two tasks in one gesture) would reintroduce a vanishing
## star with no test failing. This case fails loudly if that margin disappears.

const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")
const MissionRunnerScript := preload("res://scripts/gameplay/mission_runner.gd")

## How much slack we require between the task gap and the spam window.
const REQUIRED_SAFETY_FACTOR: float = 2.0


func test_name() -> String:
	return "rewards_pacing_invariant"


func run():
	var failures: Array = []

	var throttle_ms: int = int(RewardLedgerScript.DEFAULT_MIN_INTERVAL_MS)
	var gap_ms: float = float(MissionRunnerScript.TASK_GAP_SEC) * 1000.0

	if throttle_ms <= 0:
		failures.append("RewardLedger.DEFAULT_MIN_INTERVAL_MS should be positive, got %d" % throttle_ms)

	if gap_ms <= float(throttle_ms):
		failures.append(
			("MissionRunner.TASK_GAP_SEC (%.0f ms) must exceed "
			+ "RewardLedger.DEFAULT_MIN_INTERVAL_MS (%d ms), or a second "
			+ "legitimately-earned task silently loses its star")
			% [gap_ms, throttle_ms])
	elif gap_ms < float(throttle_ms) * REQUIRED_SAFETY_FACTOR:
		failures.append(
			("task gap %.0f ms is under %.1fx the %d ms spam window - too tight. "
			+ "Either raise TASK_GAP_SEC or scope the ledger throttle per "
			+ "completion id so distinct tasks cannot throttle each other")
			% [gap_ms, REQUIRED_SAFETY_FACTOR, throttle_ms])

	return failures
