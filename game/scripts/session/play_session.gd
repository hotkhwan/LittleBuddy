extends Node

## The play-session clock behind the "Great job today!" break card.
##
## Little Days V1 is free (owner decision, 2026-09-20): nothing is locked and
## nothing is for sale, so the one thing the product asks of a child's time is
## that it is not endless. This counts ACTIVE gameplay seconds and, once they
## pass the grown-up's threshold, says so exactly once. What happens next -- a
## soft card at a safe point, never mid-activity -- is the directors' business
## (`break_host.gd`, `break_card.gd`). Nothing here is a timer the child can
## see, and nothing here can fail a child: there is no deadline, no countdown
## and no consequence beyond a kind card with a big "Keep Playing".
##
## ## What counts, and what does not
##
## Active means the child is in a room, playing. Excluded, by construction or by
## a hold:
##
##   * the app in the background or without focus
##     (`NOTIFICATION_APPLICATION_PAUSED` / `_FOCUS_OUT`, `WM_WINDOW_FOCUS_OUT`;
##     iOS raises the focus notifications when its own permission prompt is up,
##     which is how the microphone dialog is excluded);
##   * loading -- the splash and the curtain happen BEFORE a world scene exists
##     and so before any owner is attached; a room fade inside the house holds
##     the clock with `pause_for("loading")` / `resume_for("loading")`;
##   * a speech permission request, when `SpeechService` can say so
##     (`is_requesting_permission()` is looked up by name; today's service has
##     no such method, and the focus-out above covers the OS prompt);
##   * the title screen and the Grown-ups panel: the title never attaches an
##     owner, and a HUD or room with a settings panel open holds the clock with
##     `set_held("menu", true)`.
##
## ## Threshold, once, and the snooze
##
## `sessionReminderMinutes` (0 / 5 / 10 / 15, default 5, `parent_settings_model.gd`)
## is re-read on every tick so a change in the Grown-ups panel applies at once.
## When the active seconds pass it, `threshold_reached` fires ONCE and `is_due()`
## stays true until a director answers. Keep Playing (`keep_playing()`) re-arms
## the clock behind a snooze of `SNOOZE_SECONDS` more ACTIVE seconds, so the
## same card cannot reappear the moment it was dismissed. Home
## (`mark_break_taken()`) starts a fresh session.
##
## ## One per tree, no autoload
##
## `get_or_create(tree)` parks a single instance under the root, so the count
## survives a trip through the title (the house, the Baby Room and the menu are
## one session to a child) without adding an autoload. World scenes `attach()`
## themselves as owners; the clock only runs while at least one owner is alive,
## which is what makes leaving a room stop the count without anyone remembering
## to say so. Nothing is persisted except the setting, which is the parent's.
##
## ## Headless
##
## `_process()` forwards to `tick(delta)`. A test calls `tick()` and
## `notification()` itself and never needs a frame.

## The setting's key in the profile, and its default.
const SETTING_KEY: String = "sessionReminderMinutes"
const DEFAULT_MINUTES: int = 5
## Keep Playing hides the card for this many more ACTIVE seconds.
const SNOOZE_SECONDS: float = 180.0
## The name under `/root`.
const NODE_NAME: String = "PlaySession"

## Fired once when the active seconds first pass the threshold, and once more
## after each snooze runs out. Never while held, suspended or unfocused.
signal threshold_reached(active_seconds: float)
## Fired when Keep Playing re-arms the clock.
signal snoozed(seconds: float)

var _active_seconds: float = 0.0
var _threshold_minutes: int = DEFAULT_MINUTES
var _fired: bool = false
var _snooze_left: float = 0.0
## The app: background and focus are tracked apart, because a platform may
## raise one without the other and either alone must stop the clock.
var _paused_by_app: bool = false
var _unfocused: bool = false
## Named holds. A counter per reason, so two overlapping loads resume once.
var _holds: Dictionary = {}
## The nodes whose presence means "gameplay". Instance ids -> weak refs.
var _owners: Dictionary = {}
## Optional, injectable: whatever answers `get_setting(key, default)`.
var _settings_source: Object = null
## Optional, injectable: whatever may answer `is_requesting_permission()`.
var _speech: Object = null


## -- Lifetime ---------------------------------------------------------------------

## The one clock for this tree, made on first use. Null only without a tree.
static func get_or_create(tree: SceneTree) -> Node:
	if tree == null or tree.root == null:
		return null
	var existing: Node = tree.root.get_node_or_null(NodePath(NODE_NAME))
	if existing != null:
		return existing
	var script: GDScript = load("res://scripts/session/play_session.gd") as GDScript
	var session: Node = script.new()
	session.name = NODE_NAME
	tree.root.add_child(session)
	return session


## The clock if one exists, without making one.
static func find(tree: SceneTree) -> Node:
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(NODE_NAME))


## A scene that counts as gameplay while it lives. Idempotent.
func attach(owner_node: Node) -> void:
	if owner_node == null:
		return
	_owners[owner_node.get_instance_id()] = weakref(owner_node)
	if owner_node.has_signal("tree_exited") \
			and not owner_node.is_connected("tree_exited", _on_owner_gone.bind(owner_node.get_instance_id())):
		owner_node.connect("tree_exited", _on_owner_gone.bind(owner_node.get_instance_id()))


func detach(owner_node: Node) -> void:
	if owner_node == null:
		return
	_owners.erase(owner_node.get_instance_id())


func _on_owner_gone(instance_id: int) -> void:
	_owners.erase(instance_id)


func has_owner() -> bool:
	_prune_owners()
	return not _owners.is_empty()


func _prune_owners() -> void:
	var dead: Array = []
	for id: Variant in _owners.keys():
		var ref: WeakRef = _owners[id]
		var node: Object = ref.get_ref()
		if node == null or not is_instance_valid(node):
			dead.append(id)
	for id: Variant in dead:
		_owners.erase(id)


## -- Ticking -----------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


## Advances the clock by `delta` seconds of wall time. Counts only while active.
func tick(delta: float) -> void:
	var dt: float = maxf(delta, 0.0)
	_refresh_threshold()
	if not is_counting():
		return
	_active_seconds += dt
	if _snooze_left > 0.0:
		_snooze_left = maxf(_snooze_left - dt, 0.0)
		if _snooze_left > 0.0:
			return
	if _fired or not is_enabled():
		return
	if _active_seconds >= threshold_seconds():
		_fired = true
		threshold_reached.emit(_active_seconds)


## True while a second of wall time is a second of play.
func is_counting() -> bool:
	if _paused_by_app or _unfocused:
		return false
	if not _holds.is_empty():
		return false
	if not has_owner():
		return false
	if _speech_is_requesting_permission():
		return false
	return true


## -- Holds -------------------------------------------------------------------------

## Stops the clock for `reason` until the matching `resume_for()`. Counted, so
## nested loads balance.
func pause_for(reason: String) -> void:
	var key: String = reason if not reason.is_empty() else "hold"
	_holds[key] = int(_holds.get(key, 0)) + 1


func resume_for(reason: String) -> void:
	var key: String = reason if not reason.is_empty() else "hold"
	if not _holds.has(key):
		return
	var left: int = int(_holds[key]) - 1
	if left <= 0:
		_holds.erase(key)
	else:
		_holds[key] = left


## A level-triggered hold, for callers that poll a state rather than see edges
## (a HUD's `is_world_paused()`): sets the reason held or not, whatever it was.
func set_held(reason: String, held: bool) -> void:
	var key: String = reason if not reason.is_empty() else "hold"
	if held:
		_holds[key] = 1
	else:
		_holds.erase(key)


func is_held(reason: String = "") -> bool:
	if reason.is_empty():
		return not _holds.is_empty()
	return _holds.has(reason)


func hold_count(reason: String) -> int:
	return int(_holds.get(reason, 0))


## -- The app -------------------------------------------------------------------------

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_paused_by_app = true
		NOTIFICATION_APPLICATION_RESUMED:
			_paused_by_app = false
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_unfocused = true
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_unfocused = false


func is_app_paused() -> bool:
	return _paused_by_app


func is_unfocused() -> bool:
	return _unfocused


## -- Threshold -----------------------------------------------------------------------

## Minutes from the setting; 0 means the reminder is off.
func get_threshold_minutes() -> int:
	return _threshold_minutes


## Sets the threshold directly (a test, or a settings screen applying live
## before the profile has written). Any value outside the offered ones is
## snapped to the nearest offered one; negatives read as off.
func set_threshold_minutes(minutes: int) -> void:
	_threshold_minutes = normalise_minutes(minutes)


## The offered choices. 0 is Off.
const OFFERED_MINUTES: Array[int] = [0, 5, 10, 15]


static func normalise_minutes(value: Variant) -> int:
	var minutes: int = DEFAULT_MINUTES
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		if is_finite(float(value)):
			minutes = int(round(float(value)))
	elif typeof(value) == TYPE_STRING and String(value).is_valid_int():
		minutes = int(String(value))
	if minutes <= 0:
		return 0
	var best: int = OFFERED_MINUTES[1]
	for offered: int in OFFERED_MINUTES:
		if offered == 0:
			continue
		if absi(offered - minutes) < absi(best - minutes):
			best = offered
	return best


func is_enabled() -> bool:
	return _threshold_minutes > 0


func threshold_seconds() -> float:
	return float(_threshold_minutes) * 60.0


func get_active_seconds() -> float:
	return _active_seconds


## True from the moment the threshold fires until a director answers with
## `keep_playing()` or `mark_break_taken()`.
func is_due() -> bool:
	return _fired


## Keep Playing: the card closes and the clock re-arms behind the snooze.
func keep_playing() -> void:
	_fired = false
	_snooze_left = SNOOZE_SECONDS
	snoozed.emit(SNOOZE_SECONDS)


func get_snooze_left() -> float:
	return _snooze_left


## Home: the child took the break. The next visit is a new session.
func mark_break_taken() -> void:
	_active_seconds = 0.0
	_fired = false
	_snooze_left = 0.0


## Everything back to the start, holds included. Tests.
func reset() -> void:
	mark_break_taken()
	_holds.clear()
	_paused_by_app = false
	_unfocused = false


## -- Settings ----------------------------------------------------------------------

## Whatever answers `get_setting(key, default)`; the SaveService autoload by
## default. Null restores the default lookup.
func set_settings_source(source: Object) -> void:
	_settings_source = source
	_refresh_threshold()


func _refresh_threshold() -> void:
	var source: Object = _settings()
	if source == null or not source.has_method("get_setting"):
		return
	_threshold_minutes = normalise_minutes(source.call("get_setting", SETTING_KEY, DEFAULT_MINUTES))


func _settings() -> Object:
	if _settings_source != null and is_instance_valid(_settings_source):
		return _settings_source
	return _autoload("SaveService")


## Whatever may answer `is_requesting_permission()`; SpeechService by default.
func set_speech_service(speech: Object) -> void:
	_speech = speech


func _speech_is_requesting_permission() -> bool:
	var speech: Object = _speech
	if speech == null or not is_instance_valid(speech):
		speech = _autoload("SpeechService")
	if speech == null or not speech.has_method("is_requesting_permission"):
		return false
	return bool(speech.call("is_requesting_permission"))


func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(autoload_name))
