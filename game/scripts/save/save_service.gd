extends Node

## Autoload wrapper around ProfileStore. Local-only persistence: stars,
## completed activities, and settings. No network, no cloud sync, no
## analytics, no accounts.

signal profile_changed(profile: Dictionary)
signal stars_changed(stars: int)

var _store: ProfileStore
var _profile: Dictionary = {}


func _init() -> void:
	_store = ProfileStore.new()


func _ready() -> void:
	reload_profile()


func get_stars() -> int:
	return int(_profile.get("stars", 0))


## Adds (or subtracts) stars, clamped so the total never goes negative.
## Persists immediately and emits stars_changed with the new total.
func add_stars(amount: int) -> int:
	var new_total: int = get_stars() + amount
	if new_total < 0:
		new_total = 0
	_profile["stars"] = new_total
	save_profile()
	stars_changed.emit(new_total)
	profile_changed.emit(get_profile())
	return new_total


func mark_activity_completed(activity_id: String) -> void:
	if activity_id == "":
		return
	var completed: Array = _profile.get("completedActivities", [])
	if completed.has(activity_id):
		return
	completed.append(activity_id)
	_profile["completedActivities"] = completed
	save_profile()
	profile_changed.emit(get_profile())


func is_activity_completed(activity_id: String) -> bool:
	var completed: Array = _profile.get("completedActivities", [])
	return completed.has(activity_id)


func get_setting(key: String, default_value: Variant = null) -> Variant:
	var settings: Dictionary = _profile.get("settings", {})
	if settings.has(key):
		return settings[key]
	return default_value


func set_setting(key: String, value: Variant) -> void:
	var settings: Dictionary = _profile.get("settings", {})
	settings[key] = value
	_profile["settings"] = settings
	save_profile()
	profile_changed.emit(get_profile())


func save_profile() -> bool:
	return _store.save_profile(_profile)


func reload_profile() -> void:
	_profile = _store.load_profile()
	profile_changed.emit(get_profile())
	stars_changed.emit(get_stars())


func reset_profile() -> void:
	_profile = _store.default_profile()
	save_profile()
	profile_changed.emit(get_profile())
	stars_changed.emit(get_stars())


## Returns a deep copy so callers cannot mutate internal state.
func get_profile() -> Dictionary:
	return _profile.duplicate(true)


func _notification(what: int) -> void:
	# Save whenever the app is closed or backgrounded (important on iOS,
	# where the app is paused rather than quit). Constants are checked by
	# value rather than relied upon to exist at compile time in unusual
	# export contexts, so this stays defensive across platforms.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_profile()
