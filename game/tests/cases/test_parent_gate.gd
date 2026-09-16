extends RefCounted

## Pure timing logic of the press-and-hold parental gate.
## Loaded by path rather than by `class_name` so the case does not depend on
## the editor having refreshed the global class cache.

const GateScript := preload("res://scripts/parent_settings/parental_gate.gd")


func test_name() -> String:
	return "parent_gate"


func run() -> Array:
	var failures: Array = []
	failures += _test_progress_accumulates()
	failures += _test_early_release_resets()
	failures += _test_unlocks_once()
	failures += _test_reset_allows_reuse()
	failures += _test_custom_duration()
	return failures


func _make_gate(duration: float = 3.0) -> Object:
	var gate: Object = GateScript.new()
	gate.hold_duration = duration
	return gate


## Signal counter shared by reference so the lambda can mutate it.
func _count_unlocks(gate: Object) -> Array:
	var counter: Array = [0]
	gate.unlocked.connect(func() -> void: counter[0] += 1)
	return counter


func _test_progress_accumulates() -> Array:
	var failures: Array = []
	var gate: Object = _make_gate(3.0)
	var unlocks: Array = _count_unlocks(gate)

	if gate.get_progress() != 0.0:
		failures.append("a fresh gate should start at 0.0 progress, got %f" % gate.get_progress())

	gate.begin_hold()
	if not gate.is_holding():
		failures.append("begin_hold() should put the gate into the holding state")

	gate.advance(1.0)
	if not is_equal_approx(gate.get_progress(), 1.0 / 3.0):
		failures.append("1s of a 3s hold should be 1/3 progress, got %f" % gate.get_progress())

	gate.advance(1.0)
	if not is_equal_approx(gate.get_progress(), 2.0 / 3.0):
		failures.append("2s of a 3s hold should be 2/3 progress, got %f" % gate.get_progress())

	if gate.has_unlocked() or unlocks[0] != 0:
		failures.append("the gate must not unlock before the full hold duration")

	# Time must never advance while no hold is running.
	gate.cancel_hold()
	gate.advance(10.0)
	if gate.get_progress() != 0.0 or unlocks[0] != 0:
		failures.append("advance() must be ignored when no hold is in progress")

	gate.free()
	return failures


func _test_early_release_resets() -> Array:
	var failures: Array = []
	var gate: Object = _make_gate(3.0)
	var unlocks: Array = _count_unlocks(gate)

	gate.begin_hold()
	gate.advance(2.9)
	gate.cancel_hold()

	if gate.get_progress() != 0.0:
		failures.append("releasing early must reset progress to 0, got %f" % gate.get_progress())
	if gate.is_holding():
		failures.append("releasing early must clear the holding state")
	if gate.has_unlocked() or unlocks[0] != 0:
		failures.append("releasing early must not unlock the gate")

	# It must not be stuck: a fresh hold still works and needs the full time.
	gate.begin_hold()
	gate.advance(2.9)
	if unlocks[0] != 0:
		failures.append("a restarted hold must start from zero, not from the cancelled progress")
	gate.advance(0.2)
	if unlocks[0] != 1:
		failures.append("a full hold after a cancelled one should unlock, got %d" % unlocks[0])

	gate.free()
	return failures


func _test_unlocks_once() -> Array:
	var failures: Array = []
	var gate: Object = _make_gate(3.0)
	var unlocks: Array = _count_unlocks(gate)

	gate.begin_hold()
	gate.advance(3.0)

	if unlocks[0] != 1:
		failures.append("reaching the hold duration should emit unlocked() once, got %d" % unlocks[0])
	if not gate.has_unlocked():
		failures.append("has_unlocked() should be true after a full hold")
	if gate.is_holding():
		failures.append("the gate should stop holding once it unlocks")
	if not is_equal_approx(gate.get_progress(), 1.0):
		failures.append("progress should be 1.0 after unlocking, got %f" % gate.get_progress())

	# Extra time, extra presses: still exactly one unlock.
	gate.advance(5.0)
	gate.begin_hold()
	gate.advance(5.0)
	gate.cancel_hold()
	gate.advance(5.0)
	if unlocks[0] != 1:
		failures.append("the gate must unlock exactly once until reset(), got %d" % unlocks[0])

	gate.free()
	return failures


func _test_reset_allows_reuse() -> Array:
	var failures: Array = []
	var gate: Object = _make_gate(3.0)
	var unlocks: Array = _count_unlocks(gate)

	gate.begin_hold()
	gate.advance(3.0)
	gate.reset()

	if gate.has_unlocked():
		failures.append("reset() should clear the unlocked latch")
	if gate.get_progress() != 0.0:
		failures.append("reset() should clear progress, got %f" % gate.get_progress())

	gate.begin_hold()
	gate.advance(3.0)
	if unlocks[0] != 2:
		failures.append("the gate should be reusable after reset(), got %d unlock(s)" % unlocks[0])

	gate.free()
	return failures


func _test_custom_duration() -> Array:
	var failures: Array = []
	var gate: Object = _make_gate(1.5)
	var unlocks: Array = _count_unlocks(gate)

	gate.begin_hold()
	gate.advance(0.75)
	if not is_equal_approx(gate.get_progress(), 0.5):
		failures.append("hold_duration should be honoured, got %f" % gate.get_progress())
	if unlocks[0] != 0:
		failures.append("a half-finished custom hold must not unlock")
	gate.advance(0.75)
	if unlocks[0] != 1:
		failures.append("the custom duration should unlock at 1.5s, got %d" % unlocks[0])
	gate.free()

	# A zero/negative duration must not divide by zero or report NaN.
	var degenerate: Object = _make_gate(0.0)
	if degenerate.get_progress() != 1.0:
		failures.append("a zero duration should report full progress, got %f" % degenerate.get_progress())
	degenerate.free()

	return failures
