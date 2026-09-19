class_name MusicBinder
extends Node
## Connects `AudioDirector` to what the child is actually doing.
##
##     var audio := AudioDirector.new()
##     root.add_child(audio)          # as an autoload, this is automatic
##
## The director knows how to play music; this knows when. Keeping them apart is
## what lets the director stay testable with no tree, no scene and no mixer, and
## it is why every game script in this project can stay unaware that music exists.
##
## ## It connects to the game, and the game does not connect to it
##
## Nothing in `scripts/house/`, `scripts/gameplay/`, `scripts/ui/` or `scenes/`
## mentions music, and nothing needs to. This node watches
## `SceneTree.node_added`, recognises the handful of nodes whose signals describe
## "where is the child", and connects to them. The cost is one dictionary lookup
## per node added; the benefit is that music is a pure addition rather than an
## edit spread across a dozen gameplay files, and deleting this one file removes
## it completely.
##
## Nodes are recognised by SCRIPT PATH rather than by `class_name`, because most
## of them have no `class_name` (`house_world.gd`, `house_level_director.gd`,
## `house_freeplay_director.gd`) and because a path is checkable in a test without
## instantiating a 3D scene.
##
## ## The mapping, and what is deliberately NOT in it
##
##     main.gd added                        -> menu
##     house_world.gd added / room_entered  -> house
##     mission_started / level_started      -> miniGame
##     mission_completed / level_finished   -> (stays on miniGame; see below)
##     session_summary closed/again/next    -> house
##
## **`task_plan_changed` and `transition_started` are not connected, on purpose.**
## An objective changing and a child walking through a door are the two things
## that happen most often in a mission, and re-requesting music on either is how a
## soundtrack ends up stuttering back to bar one every few seconds. `room_entered`
## IS connected -- it is how free exploration is detected -- but it is ignored
## while a mission is running, so mission 01's four room changes cannot interrupt
## the mission's own music. `AudioDirector.set_state()` is also idempotent, so
## even a duplicated request is a no-op rather than a restart.
##
## **`reward` is not requested either.** No reward track has been delivered, so
## asking for it would replace the mission's music with silence at the exact
## moment the child is being congratulated. Instead the mission music plays on
## through the celebration and stops when the summary is dismissed. The day a
## third track arrives, this becomes one line here plus one manifest row -- see
## `REWARD_STATE_NOTE`.
##
## ## Ducking is polled, not signalled
##
## `TtsService` emits a balanced `speech_started`/`speech_finished` pair, but
## `SpeechService.listening_stopped` is NOT guaranteed: the iOS backend's
## `_on_recognition_failed()` re-emits a failure without clearing its listening
## flag, and `permission_result(false)` emits no stop at all. A duck keyed on
## those signals would stick, and music that went quiet and stayed quiet is a bug
## a parent would report as "the music is broken".
##
## So this asks, every frame, `is_speaking() or is_listening()`. One frame of
## latency (~16 ms) is inaudible, there is no edge to miss, and a stuck duck is
## structurally impossible. Both services are duck-typed, so a build with neither
## autoload simply never ducks.
##
## No network. No microphone. It only reads.

## The state names come from the state machine, not from `AudioDirector`, so this
## file does not preload the director that creates it. A preload cycle between the
## two would fail to compile.
const BgmMachine := preload("res://scripts/audio/bgm_state_machine.gd")

## Scene/script paths this node recognises. Constants rather than literals so a
## test can assert the files still exist -- a silently renamed script would
## otherwise turn music off with no failure anywhere.
const MENU_SCRIPT: String = "res://scenes/main/main.gd"
const HOUSE_WORLD_SCRIPT: String = "res://scripts/house/house_world.gd"
const LEVEL_DIRECTOR_SCRIPT: String = "res://scripts/gameplay/house_level_director.gd"
const MISSION_RUNNER_SCRIPTS: Array[String] = [
	"res://scripts/gameplay/mission_runner.gd",
	"res://scripts/gameplay/house_mission_runner.gd",
]
const SUMMARY_SCRIPT: String = "res://scenes/progression/session_summary.gd"

const TTS_SERVICE_PATH: String = "/root/TtsService"
const SPEECH_SERVICE_PATH: String = "/root/SpeechService"

## Kept as a constant so the intent survives in the file rather than in a commit
## message. See the class docs.
const REWARD_STATE_NOTE: String = (
	"AudioDirector.STATE_REWARD is intentionally never requested: no reward track "
	+ "exists, so requesting it would silence the mission music during the "
	+ "celebration. Add a track with usageScenes [\"reward\"] and connect "
	+ "level_finished here to enable it."
)

## The music state changed because of something the child did. `source` names the
## signal or node that caused it, for the runbook and for tests.
signal state_requested(state: String, source: String)

var _director: Node = null
var _mission_running: bool = false
var _bound: Dictionary = {}
var _tts: Node = null
var _speech: Node = null


func _ready() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.node_added.connect(_on_node_added)
	# The world may already be in the tree -- a scene run directly from the editor,
	# or a test that builds it before installing audio. Adopt what is there.
	adopt_existing_tree()


func _process(_delta: float) -> void:
	_update_duck()


# -----------------------------------------------------------------------------
# Wiring
# -----------------------------------------------------------------------------


## Hands this binder the director it drives. Duck-typed: anything with
## `set_state()` and `set_ducked()` works, which is what lets the tests drive it
## with a spy and no audio at all.
func bind_director(director: Node) -> void:
	_director = director


func director() -> Node:
	return _director if is_instance_valid(_director) else null


## Walks the current tree and binds anything already in it. Idempotent.
func adopt_existing_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	_adopt_recursive(tree.root)


func _adopt_recursive(node: Node) -> void:
	_on_node_added(node)
	for child: Node in node.get_children():
		_adopt_recursive(child)


func _on_node_added(node: Node) -> void:
	if node == null or node == self:
		return
	var script_path: String = _script_path_of(node)
	if script_path.is_empty():
		return

	if script_path == MENU_SCRIPT:
		# Returning to the title screen ends any mission that was running.
		_mission_running = false
		_request(BgmMachine.STATE_MENU, "main.gd entered the tree")
		return

	if script_path == HOUSE_WORLD_SCRIPT:
		_connect_once(node, "room_entered", _on_room_entered)
		if not _mission_running:
			_request(BgmMachine.STATE_HOUSE, "house_world.gd entered the tree")
		return

	if script_path == LEVEL_DIRECTOR_SCRIPT:
		_connect_once(node, "level_started", _on_level_started)
		_connect_once(node, "level_finished", _on_level_finished)
		# `task_plan_changed` is deliberately NOT connected. See the class docs.
		return

	if MISSION_RUNNER_SCRIPTS.has(script_path):
		_connect_once(node, "mission_started", _on_mission_started)
		_connect_once(node, "mission_completed", _on_mission_completed)
		return

	if script_path == SUMMARY_SCRIPT:
		_connect_once(node, "closed", _on_summary_dismissed)
		_connect_once(node, "play_again", _on_summary_dismissed)
		_connect_once(node, "next_level", _on_summary_dismissed)
		return


## Connects `signal_name` on `node` exactly once, tolerating a node that does not
## declare it. Returns whether the connection is in place.
##
## The `_bound` key includes the node's instance id, so a freed-and-rebuilt world
## rebinds rather than being remembered as already done.
func _connect_once(node: Node, signal_name: String, handler: Callable) -> bool:
	if node == null or not node.has_signal(signal_name):
		return false
	var key: String = "%d|%s" % [node.get_instance_id(), signal_name]
	if _bound.has(key):
		return true
	if node.is_connected(signal_name, handler):
		_bound[key] = true
		return true
	if node.connect(signal_name, handler) != OK:
		return false
	_bound[key] = true
	return true


static func _script_path_of(node: Node) -> String:
	var script: Variant = node.get_script()
	if script == null or not (script is Script):
		return ""
	return (script as Script).resource_path


# -----------------------------------------------------------------------------
# What the child is doing
# -----------------------------------------------------------------------------


## Free exploration. Ignored while a mission is running: mission 01 walks the
## child through four rooms, and each of those raises this.
func _on_room_entered(room_id: String, _spawn_id: String) -> void:
	if _mission_running:
		return
	_request(BgmMachine.STATE_HOUSE, "room_entered(%s)" % room_id)


func _on_level_started(level_id: String, _mission_id: String, _task_count: int) -> void:
	_mission_running = true
	_request(BgmMachine.STATE_MINI_GAME, "level_started(%s)" % level_id)


func _on_mission_started(mission_id: String, _total: int) -> void:
	_mission_running = true
	_request(BgmMachine.STATE_MINI_GAME, "mission_started(%s)" % mission_id)


## The mission is over but the celebration is not. The music carries on until the
## summary is dismissed -- see `REWARD_STATE_NOTE`.
func _on_mission_completed(_mission_id: String, _stars: int) -> void:
	_mission_running = false


func _on_level_finished(_level_id: String, _stars: int) -> void:
	_mission_running = false


func _on_summary_dismissed() -> void:
	_mission_running = false
	_request(BgmMachine.STATE_HOUSE, "session summary dismissed")


## True while a mission owns the music. Diagnostics and tests.
func is_mission_running() -> bool:
	return _mission_running


func _request(state: String, source: String) -> void:
	var audio: Node = director()
	if audio == null or not audio.has_method("set_state"):
		return
	if audio.has_method("current_state") and String(audio.call("current_state")) == state:
		return  # Already there. Re-requesting would be a no-op anyway; say nothing.
	audio.call("set_state", state)
	state_requested.emit(state, source)


# -----------------------------------------------------------------------------
# Ducking
# -----------------------------------------------------------------------------


## True when the game is speaking English or listening for it, so music should be
## out of the way. Polled; see the class docs on why this is not signal-driven.
func should_duck() -> bool:
	var tts: Node = _service(TTS_SERVICE_PATH, "_tts")
	if tts != null and tts.has_method("is_speaking") and bool(tts.call("is_speaking")):
		return true
	var speech: Node = _service(SPEECH_SERVICE_PATH, "_speech")
	if speech != null and speech.has_method("is_listening") and bool(speech.call("is_listening")):
		return true
	return false


func _update_duck() -> void:
	var audio: Node = director()
	if audio == null or not audio.has_method("set_ducked"):
		return
	audio.call("set_ducked", should_duck())


## Resolves a speech autoload, cached. Absent is normal: the headless runner
## detaches the autoloads, and a build with no speech at all must still have music.
func _service(path: String, field: String) -> Node:
	var cached: Variant = get(field)
	if cached is Node and is_instance_valid(cached):
		return cached
	if not is_inside_tree():
		return null
	var found: Node = get_node_or_null(path)
	set(field, found)
	return found
