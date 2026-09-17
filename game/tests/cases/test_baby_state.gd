extends RefCounted

# NOTE: signal callbacks use a member method (not a local lambda) because
# GDScript lambdas capture enclosing local variables by value, not by
# reference — mutating them inside the lambda would not be observable here.
var _received_stat: String = ""
var _received_value: float = -1.0
var _received_count: int = 0


func test_name() -> String:
	return "baby_state"


func run():
	var failures: Array = []

	var state: BabyState = BabyState.new()

	if state.hunger != 80.0:
		failures.append("expected initial hunger 80.0, got %s" % state.hunger)
	if state.happiness != 50.0:
		failures.append("expected initial happiness 50.0, got %s" % state.happiness)
	if state.energy != 70.0:
		failures.append("expected initial energy 70.0, got %s" % state.energy)
	if state.cleanliness != 70.0:
		failures.append("expected initial cleanliness 70.0, got %s" % state.cleanliness)

	if not state.is_hungry():
		failures.append("expected baby to start hungry (hunger 80 >= threshold)")

	state.stat_changed.connect(_on_stat_changed)

	state.feed(50.0)

	if state.hunger != 30.0:
		failures.append("expected hunger 30.0 after feed(50.0), got %s" % state.hunger)
	if state.happiness <= 50.0:
		failures.append("expected happiness to increase after feeding, got %s" % state.happiness)
	if _received_count == 0:
		failures.append("expected stat_changed signal to fire on feed()")
	if _received_stat != "hunger" and _received_stat != "happiness":
		failures.append("expected stat_changed to report hunger or happiness, got %s" % _received_stat)
	if _received_value != state.happiness and _received_value != state.hunger:
		failures.append("expected stat_changed to report a value matching current state")

	if state.is_hungry():
		failures.append("expected baby to no longer be hungry after feed(50.0) from 80 -> 30")

	# Clamping never exceeds [0, 100].
	state.set_hunger(-999.0)
	if state.hunger != 0.0:
		failures.append("expected hunger clamped to 0.0, got %s" % state.hunger)

	state.set_happiness(999.0)
	if state.happiness != 100.0:
		failures.append("expected happiness clamped to 100.0, got %s" % state.happiness)

	return failures


func _on_stat_changed(stat_name: String, value: float) -> void:
	_received_stat = stat_name
	_received_value = value
	_received_count += 1
