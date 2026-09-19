extends RefCounted
## Music following the real game: the binder, the speech duck, and the licence
## override.
##
## ## Why the binder is tested without a scene
##
## `MusicBinder` recognises gameplay nodes by SCRIPT PATH and then connects to
## their signals. Both halves can be checked without instantiating a 3D world:
## the paths are files, and a `GDScript`'s declared signals are readable from the
## script resource. That is deliberate -- it means a renamed script or a renamed
## signal fails HERE, loudly, instead of silently switching music off in a build
## that still passes every other test. `tests/smoke_audio_shipping.gd` covers the
## other half by driving the real scenes.
##
## ## The headline assertions
##
## 1. A room transition during a mission must NOT touch the music. Mission 01
##    walks the child through four rooms; if each one re-requested music the
##    soundtrack would stutter back to bar one every few seconds.
## 2. The licence override cannot be armed by anything in this repository, cannot
##    soften `MusicManifest`, and cannot conjure a track that has no file or whose
##    rights are `"denied"`.
## 3. Ducking only ever attenuates, and never above the music ceiling.

const BINDER_SCRIPT: String = "res://scripts/audio/music_binder.gd"
const DIRECTOR_SCRIPT: String = "res://scripts/audio/audio_director.gd"
const MANIFEST_SCRIPT: String = "res://scripts/audio/music_manifest.gd"
const OVERRIDE_SCRIPT: String = "res://scripts/audio/music_licence_override.gd"
const SHIPPED_MANIFEST: String = "res://content/audio/manifest.json"

## The file this project ships a real, delivered, UNVERIFIED track as. Used to
## prove the override needs a real file and cannot invent one.
const A_REAL_TRACK_FILE: String = "res://audio/music/hungry_bunny.ogg"

## Every gameplay signal the binder depends on, by the script that must declare
## it. A rename anywhere in this table breaks music silently, so it is asserted.
const REQUIRED_SIGNALS: Dictionary = {
	"res://scripts/house/house_world.gd": ["room_entered"],
	"res://scripts/gameplay/house_level_director.gd": ["level_started", "level_finished"],
	"res://scripts/gameplay/mission_runner.gd": ["mission_started", "mission_completed"],
	"res://scenes/progression/session_summary.gd": ["closed", "play_again", "next_level"],
}

## A director stand-in. Records what it was asked for instead of playing anything,
## so the binder's decisions are visible with no audio, no manifest and no tree.
const SPY_SOURCE: String = """
extends Node
var states: Array = []
var ducks: Array = []
var state: String = "silent"
func set_state(value: String) -> bool:
	states.append(value)
	state = value
	return true
func current_state() -> String:
	return state
func set_ducked(value: bool) -> void:
	ducks.append(value)
"""

## Stands in for TtsService / SpeechService. Duck-typed exactly as the real ones.
const SPEECH_STUB_SOURCE: String = """
extends Node
var speaking: bool = false
var listening: bool = false
func is_speaking() -> bool:
	return speaking
func is_listening() -> bool:
	return listening
"""

var _binder_script: GDScript = null
var _director_script: GDScript = null


func test_name() -> String:
	return "audio_music_binder"


func run():
	var failures: Array = []

	for path: String in [BINDER_SCRIPT, DIRECTOR_SCRIPT, OVERRIDE_SCRIPT]:
		var resource: Resource = load(path)
		if resource == null or not (resource is GDScript):
			failures.append("could not load %s" % path)
	if not failures.is_empty():
		return failures
	_binder_script = load(BINDER_SCRIPT) as GDScript
	_director_script = load(DIRECTOR_SCRIPT) as GDScript

	failures.append_array(_test_the_nodes_it_watches_still_exist())
	failures.append_array(_test_the_signals_it_connects_still_exist())
	failures.append_array(_test_the_state_mapping())
	failures.append_array(_test_a_mission_is_not_interrupted())
	failures.append_array(_test_ducking())
	failures.append_array(_test_the_duck_only_attenuates())
	failures.append_array(_test_the_licence_override_is_disarmed())
	failures.append_array(_test_the_override_cannot_soften_the_gate())
	failures.append_array(_test_the_override_needs_a_real_file())

	return failures


# -----------------------------------------------------------------------------
# 1. The wiring surface
# -----------------------------------------------------------------------------


## The binder matches on script paths. A path that no longer exists is not a
## compile error, not a warning and not a crash -- it is silence, which is the one
## failure mode this whole subsystem is designed to make impossible to ship
## unnoticed. So it is a test.
func _test_the_nodes_it_watches_still_exist():
	var failures: Array = []

	var watched: Array = [
		_binder_script.MENU_SCRIPT,
		_binder_script.HOUSE_WORLD_SCRIPT,
		_binder_script.LEVEL_DIRECTOR_SCRIPT,
		_binder_script.SUMMARY_SCRIPT,
	]
	watched.append_array(_binder_script.MISSION_RUNNER_SCRIPTS)

	for path: String in watched:
		if not ResourceLoader.exists(path):
			failures.append(
				("MusicBinder watches for %s, which does not exist. Music would never start and "
				+ "nothing else would fail.") % path
			)

	return failures


## Same argument one level down: the binder calls `connect()` on names it does not
## own. `_connect_once()` tolerates a missing signal at runtime rather than
## crashing the game -- which is right, and which is exactly why the guarantee has
## to live in a test instead of in an exception.
func _test_the_signals_it_connects_still_exist():
	var failures: Array = []

	for path: Variant in REQUIRED_SIGNALS.keys():
		var script_path: String = String(path)
		var script: Resource = load(script_path)
		if script == null or not (script is GDScript):
			failures.append("could not load %s to check its signals" % script_path)
			continue
		var declared: Array = []
		for entry: Dictionary in (script as GDScript).get_script_signal_list():
			declared.append(String(entry.get("name", "")))
		for signal_name: Variant in REQUIRED_SIGNALS[path] as Array:
			if not declared.has(String(signal_name)):
				failures.append(
					("%s no longer declares `%s`, which MusicBinder connects to. Music would "
					+ "stop following the game. Declared: %s")
					% [script_path, String(signal_name), str(declared)]
				)

	return failures


# -----------------------------------------------------------------------------
# 2. The mapping
# -----------------------------------------------------------------------------


func _test_the_state_mapping():
	var failures: Array = []

	var binder: Node = _binder_script.new()
	var spy: Node = _spy()
	binder.bind_director(spy)

	# Menu.
	binder._request(binder.BgmMachine.STATE_MENU, "test")
	# Into the house.
	binder._on_room_entered("kitchen", "default")
	# A mission starts.
	binder._on_level_started("imHungry", "imHungry", 7)
	# It ends, and the celebration runs.
	binder._on_level_finished("imHungry", 3)
	# The summary is dismissed.
	binder._on_summary_dismissed()

	var expected: Array = ["menu", "house", "miniGame", "house"]
	if str(spy.states) != str(expected):
		failures.append(
			"the binder asked for %s; expected %s" % [str(spy.states), str(expected)]
		)

	# `reward` must never be requested while no reward track exists: it would
	# replace the mission's music with silence during the celebration.
	if spy.states.has("reward"):
		failures.append(
			"the binder requested 'reward'. %s" % String(_binder_script.REWARD_STATE_NOTE)
		)

	# An already-satisfied request must not reach the director at all.
	var before: int = spy.states.size()
	binder._on_summary_dismissed()
	binder._on_room_entered("bedroom", "default")
	if spy.states.size() != before:
		failures.append(
			"re-requesting the state the director is already in reached it %d extra time(s)"
					% [spy.states.size() - before]
		)

	binder.free()
	spy.free()
	return failures


## THE headline case. Mission 01 walks the child through four rooms, and a mission
## also changes its objective seven times. Neither may restart the music.
func _test_a_mission_is_not_interrupted():
	var failures: Array = []

	var binder: Node = _binder_script.new()
	var spy: Node = _spy()
	binder.bind_director(spy)

	binder._on_room_entered("kitchen", "default")   # free exploration -> house
	binder._on_mission_started("imHungry", 7)       # -> miniGame
	var during: int = spy.states.size()

	for room_id: String in ["livingRoom", "bedroom", "bathroom", "kitchen", "livingRoom"]:
		binder._on_room_entered(room_id, "default")
	if spy.states.size() != during:
		failures.append(
			("%d room transitions during a mission changed the music (%s). Mission 01 walks the "
			+ "child through four rooms; the music must not restart at each one.")
			% [5, str(spy.states)]
		)
	if String(spy.current_state()) != "miniGame":
		failures.append(
			"the music ended up in '%s' after walking around during a mission"
					% String(spy.current_state())
		)

	# `task_plan_changed` is not connected at all, which is the strongest possible
	# guarantee about objective changes. Assert the binder has no handler for it, so
	# that connecting one later is a deliberate act with a failing test to answer.
	if binder.has_method("_on_task_plan_changed"):
		failures.append(
			"MusicBinder has grown a task_plan_changed handler. An objective changing must not "
			+ "touch the music; see the class docs before adding one."
		)

	# The mission ending does not change the music either: the celebration keeps it.
	binder._on_mission_completed("imHungry", 3)
	if spy.states.size() != during:
		failures.append(
			"finishing the mission changed the music to '%s'; the celebration should keep it"
					% String(spy.current_state())
		)
	if binder.is_mission_running():
		failures.append("the binder still thinks a mission is running after mission_completed")

	binder.free()
	spy.free()
	return failures


# -----------------------------------------------------------------------------
# 3. Ducking
# -----------------------------------------------------------------------------


func _test_ducking():
	var failures: Array = []

	var binder: Node = _binder_script.new()
	var spy: Node = _spy()
	binder.bind_director(spy)

	# No speech services at all -- the headless runner detaches them, and a build
	# with no speech must still have music.
	if binder.should_duck():
		failures.append("the binder wants to duck with no speech services present")

	var tts: Node = _speech_stub()
	var speech: Node = _speech_stub()
	binder._tts = tts
	binder._speech = speech

	if binder.should_duck():
		failures.append("the binder wants to duck while nothing is speaking or listening")

	tts.speaking = true
	if not binder.should_duck():
		failures.append("the binder does not duck while the game is SPEAKING English")
	tts.speaking = false
	speech.listening = true
	if not binder.should_duck():
		failures.append(
			"the binder does not duck while the microphone is OPEN. The child is being asked to "
			+ "say a word; the music must be out of the way."
		)
	# Overlapping is the normal case -- a prompt ends and listening begins.
	tts.speaking = true
	if not binder.should_duck():
		failures.append("the binder does not duck while both speaking and listening")
	tts.speaking = false
	speech.listening = false
	if binder.should_duck():
		failures.append(
			"the duck is still wanted after both services went quiet. A stuck duck is music that "
			+ "goes quiet and stays quiet, which is why this is POLLED and not signal-driven: "
			+ "SpeechService.listening_stopped is not guaranteed to fire."
		)

	# The binder must assert the duck state it wants rather than toggling, so a
	# missed edge cannot leave the mix wrong.
	binder._update_duck()
	if spy.ducks.is_empty():
		failures.append("_update_duck() never told the director anything")
	elif bool(spy.ducks[-1]):
		failures.append("_update_duck() asked for a duck with nothing speaking")

	binder.free()
	spy.free()
	tts.free()
	speech.free()
	return failures


## The duck is a gain, and a gain that could exceed 1.0 would let a prompt make
## music LOUDER than the ceiling the manifest enforces.
func _test_the_duck_only_attenuates():
	var failures: Array = []

	var director: Node = _director_script.new()
	director.warn_on_licence_refusal = false

	if director.is_ducked():
		failures.append("a fresh director starts ducked")
	if not is_equal_approx(float(director.duck_gain()), 1.0):
		failures.append("a fresh director's duck gain is %.3f, not 1.0" % director.duck_gain())

	director.set_ducked(true)
	if not director.is_ducked():
		failures.append("set_ducked(true) did not take")
	# Mid-ramp: partway down, never past the target and never above 1.0.
	director.advance(0.05)
	var mid: float = float(director.duck_gain())
	if mid >= 1.0 or mid <= float(director.duck_target_gain()):
		failures.append(
			"the duck jumped straight to %.3f instead of ramping towards %.3f"
					% [mid, director.duck_target_gain()]
		)
	director.finish_duck()
	if not is_equal_approx(float(director.duck_gain()), float(director.duck_target_gain())):
		failures.append("finish_duck() left the gain at %.3f" % director.duck_gain())

	# Whatever `duck_db` is set to, the gain never rises above 1.0 and the audible
	# level never rises above the music ceiling.
	var ceiling: float = load(MANIFEST_SCRIPT).MAX_VOLUME_DB
	for requested: float in [-40.0, -10.0, 0.0, 6.0, 120.0]:
		director.duck_db = requested
		director.set_ducked(true)
		director.finish_duck()
		if float(director.duck_gain()) > 1.0 + 0.0001:
			failures.append(
				"duck_db %.1f produced a gain of %.3f, which would make music LOUDER"
						% [requested, director.duck_gain()]
			)
		if float(director.audible_music_volume_db()) > ceiling + 0.0001:
			failures.append(
				"duck_db %.1f let the audible level reach %.1f dB, above the %.1f dB ceiling"
						% [requested, director.audible_music_volume_db(), ceiling]
			)

	# Releasing returns to exactly 1.0, not approximately.
	director.duck_db = director.DEFAULT_DUCK_DB
	director.set_ducked(false)
	director.advance(10.0)
	if float(director.duck_gain()) != 1.0:
		failures.append(
			"releasing the duck settled at %.6f instead of exactly 1.0; music would sit "
			+ "permanently below where the parent set it" % director.duck_gain()
		)

	director.free()
	return failures


# -----------------------------------------------------------------------------
# 4. The licence override
# -----------------------------------------------------------------------------


## Nothing in this repository may arm it. If this case ever fails, a marker file
## was left behind or a committed file grew the flag.
func _test_the_licence_override_is_disarmed():
	var failures: Array = []

	var override: GDScript = load(OVERRIDE_SCRIPT) as GDScript
	if override.is_armed():
		failures.append(
			("MusicLicenceOverride.is_armed() is true during the test suite (%s). Unverified "
			+ "music must be silent unless a human deliberately armed it for one session.")
			% String(override.describe())
		)
	if override.has_marker_file():
		failures.append(
			"%s exists. It is a per-machine preview switch and must never be committed or left "
			+ "behind." % String(override.MARKER_PATH)
		)

	var director: Node = _director_script.new()
	director.warn_on_licence_refusal = false
	if director.allow_unverified_music:
		failures.append("a fresh AudioDirector has allow_unverified_music true")
	if not director.overridden_track_ids().is_empty():
		failures.append(
			"a disarmed director reports overridden tracks: %s" % str(director.overridden_track_ids())
		)
	director.free()

	return failures


## Arming the override must change ONE thing -- whether this director assigns a
## stream. It must not touch the gate, because the gate is what every shipping
## check reads.
func _test_the_override_cannot_soften_the_gate():
	var failures: Array = []

	var director: Node = _director_script.new()
	director.warn_on_licence_refusal = false
	var catalogue: RefCounted = load(MANIFEST_SCRIPT).new()
	catalogue.load_file(SHIPPED_MANIFEST)

	director.allow_unverified_music = true
	for track_id: String in catalogue.track_ids():
		if catalogue.is_playable(track_id):
			failures.append(
				("MusicManifest.is_playable('%s') is true while the override is armed. The gate "
				+ "must never soften: it is what licence_refused_track_ids() and every shipping "
				+ "check read.") % track_id
			)
		if not catalogue.licence_refused_track_ids().has(track_id):
			failures.append(
				"'%s' is not in licence_refused_track_ids() while it has no evidence" % track_id
			)

	# And the override is reported, not hidden.
	var announced: Array = []
	director.unverified_music_allowed.connect(
		func(track_id: String, _reason: String) -> void: announced.append(track_id)
	)
	director.set_state(director.STATE_MENU)
	if announced.is_empty():
		failures.append(
			"a track played under the override without emitting unverified_music_allowed. A "
			+ "preview that looks like a shipping build is how unlicensed audio gets shipped."
		)
	# Once per track, not once per transition.
	var first: int = announced.size()
	director.set_state(director.STATE_SILENT)
	director.set_state(director.STATE_MENU)
	if announced.size() != first:
		failures.append("unverified_music_allowed repeated per transition (%d -> %d)"
				% [first, announced.size()])

	director.free()
	return failures


## The override lets a paperwork problem through. It must not let anything else
## through: no file, an unknown id and an explicit `"denied"` all stay refused.
func _test_the_override_needs_a_real_file():
	var failures: Array = []

	var director: Node = _director_script.new()
	director.warn_on_licence_refusal = false
	director.allow_unverified_music = true

	var catalogue: RefCounted = load(MANIFEST_SCRIPT).new()
	catalogue.ingest_dictionary({
		"manifestVersion": 1,
		"musicDir": "res://audio/music",
		"tracks": [
			_row("pendingWithFile", "pending", "OWNER TO CONFIRM", A_REAL_TRACK_FILE, ["menu"]),
			_row("pendingNoFile", "pending", "OWNER TO CONFIRM",
					"res://audio/music/not_delivered.ogg", ["house"]),
			_row("deniedWithFile", "denied", "the licence forbids commercial use",
					A_REAL_TRACK_FILE, ["miniGame"]),
		],
	})
	director.set_manifest(catalogue)

	if not director.may_play("pendingWithFile"):
		failures.append(
			"the override did not allow a delivered track whose only problem is unrecorded rights"
		)
	if director.may_play("pendingNoFile"):
		failures.append(
			"the override allowed a track with NO FILE. It exists to release a paperwork "
			+ "refusal, not to invent audio."
		)
	if director.may_play("deniedWithFile"):
		failures.append(
			"the override allowed a track whose rights are explicitly \"denied\". Someone "
			+ "checked, and the answer was no."
		)
	if director.may_play("noSuchTrack"):
		failures.append("the override allowed an unknown track id")

	# And the state that maps to the denied track stays silent.
	director.set_state(director.STATE_MINI_GAME)
	director.finish_fades()
	if director.is_playing_music():
		failures.append(
			"a state whose only track is \"denied\" played music with the override armed"
		)

	director.free()
	return failures


# -----------------------------------------------------------------------------
# Fixtures
# -----------------------------------------------------------------------------


func _spy() -> Node:
	return _node_from_source(SPY_SOURCE)


func _speech_stub() -> Node:
	return _node_from_source(SPEECH_STUB_SOURCE)


## Builds a throwaway node from inline source. Cheaper and clearer than a fixture
## file, and it keeps the stubs next to the assertions that use them.
func _node_from_source(source: String) -> Node:
	var script: GDScript = GDScript.new()
	script.source_code = source
	script.reload()
	var node: Node = Node.new()
	node.set_script(script)
	return node


func _row(
	track_id: String, commercial_use: String, evidence: String,
	local_path: String, scenes: Array
) -> Dictionary:
	return {
		"trackId": track_id,
		"source": "test fixture",
		"createdAt": "",
		"downloadedAt": "",
		"licenseEvidence": evidence,
		"commercialUse": commercial_use,
		"localPath": local_path,
		"loopStart": 0.0,
		"loopEnd": 0.0,
		"volumeDb": -14.0,
		"usageScenes": scenes,
	}
