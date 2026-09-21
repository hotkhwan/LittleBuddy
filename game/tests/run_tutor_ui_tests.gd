extends "res://tests/run_tests.gd"

## Focused lesson routing, face-clearance, microphone and flashcard checks.
func _discover_cases() -> PackedStringArray:
	var paths := PackedStringArray()
	for path in super._discover_cases():
		if path.contains("tutor") or path.contains("flashcard"):
			paths.append(path)
	return paths
