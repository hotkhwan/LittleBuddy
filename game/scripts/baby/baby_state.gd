class_name BabyState
extends RefCounted

## Simple bounded stat container for the baby character.
## Only `hunger` affects gameplay tonight; the rest exist for future milestones.

signal stat_changed(stat_name: String, value: float)

const MIN_VALUE: float = 0.0
const MAX_VALUE: float = 100.0
## Higher hunger value == hungrier. Baby starts at 80 (hungry) so the MVP flow
## begins with the baby already needing to be fed.
const HUNGRY_THRESHOLD: float = 40.0

var hunger: float = 80.0
var happiness: float = 50.0
var energy: float = 70.0
var cleanliness: float = 70.0


func _clamp_stat(value: float) -> float:
	return clampf(value, MIN_VALUE, MAX_VALUE)


func set_hunger(value: float) -> void:
	hunger = _clamp_stat(value)
	stat_changed.emit("hunger", hunger)


func set_happiness(value: float) -> void:
	happiness = _clamp_stat(value)
	stat_changed.emit("happiness", happiness)


func set_energy(value: float) -> void:
	energy = _clamp_stat(value)
	stat_changed.emit("energy", energy)


func set_cleanliness(value: float) -> void:
	cleanliness = _clamp_stat(value)
	stat_changed.emit("cleanliness", cleanliness)


## Feeds the baby: reduces hunger by `amount` (default 50) and nudges happiness up a little.
func feed(amount: float = 50.0) -> void:
	set_hunger(hunger - amount)
	set_happiness(happiness + 10.0)


func is_hungry() -> bool:
	return hunger >= HUNGRY_THRESHOLD
