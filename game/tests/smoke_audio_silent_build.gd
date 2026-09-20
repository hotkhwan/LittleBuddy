extends SceneTree

## The SHIPPING default, proven in the real game: the music is silent, and the
## game is whole.
##
##   Godot --headless --path game --script res://tests/smoke_audio_silent_build.gd
##
## `smoke_audio_shipping.gd` proves that the two delivered tracks really play --
## but to do that it has to ARM `MusicLicenceOverride` before it loads a single
## scene, so everything it shows from the menu onwards is a preview and not a
## build. This file is the other half, and the half that matters legally: the real
## `/root/Audio` autoload, the real `main.tscn` and `house_world.tscn`, a real
## mission, and **nothing armed**.
##
## The expected result is SILENCE, and silence is the PASS. What is actually being
## asserted is that the silence has the right cause and no side effects:
##
##   1. nothing on this machine armed the override -- no flag, no marker file;
##   2. both .ogg files are present, decodable, and the right length, so the
##      silence is not a broken resource path;
##   3. the licence gate refuses them for `commercialUseUnverified` -- the
##      paperwork -- and NOT for `fileMissing`;
##   4. no `AudioStreamPlayer` anywhere in the real running tree ever holds a
##      music stream: not in the menu, not in the house, not during a mission;
##   5. the mission still runs and room transitions still work, so the game is
##      fully playable silent;
##   6. speech and sound effects are unaffected -- the silence is MUSIC ONLY.
##
## A failure here means either that unverified music escaped into a normal build
## (points 3-4) or that the silence is hiding a real breakage (points 2, 5, 6).

const OVERRIDE_SCRIPT: String = "res://scripts/audio/music_licence_override.gd"
const MENU_SCENE: String = "res://scenes/main/main.tscn"
const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"

const MENU_TRACK: String = "littleDaysTheme"
const MISSION_TRACK: String = "hungryBunny"
const MISSION: String = "imHungry"

## The one refusal that means "the paperwork is not done". Anything else here
## would mean the silence has a different, worse cause.
const EXPECTED_REFUSAL: String = "commercialUseUnverified"
const MANIFEST_SCRIPT: String = "res://scripts/audio/music_manifest.gd"
const PENDING_FIXTURE: String = "res://tests/fixtures/audio_manifest_pending.json"

var _fail: Array = []
var _director: Node = null
var _reasons: Dictionary = {}
var _started: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	print("=== proving the SILENT PATH: unverified music is silent (pending fixture manifest) ===")
	# AFTER a frame: autoloads are not attached to `root` yet when a `--script`
	# SceneTree initialises. Same reason as smoke_mission01.gd.
	await process_frame

	# ------------------------------------------------- 1. NOTHING IS ARMED
	var override: GDScript = load(OVERRIDE_SCRIPT) as GDScript
	if override == null:
		return _die("cannot load %s" % OVERRIDE_SCRIPT)
	print("1. licence override: %s" % String(override.describe()))
	if bool(override.is_armed()):
		# Not a code failure, and not something to assert past: this file's entire
		# subject is the disarmed state, so an armed machine cannot answer the
		# question at all.
		return _die(
			("the licence override is ARMED on this machine (%s), so the shipping default "
			+ "cannot be measured. Disarm it -- delete %s and drop %s -- and run this again. "
			+ "Use smoke_audio_shipping.gd to hear the tracks.")
			% [String(override.describe()), String(override.MARKER_PATH),
				String(override.CLI_FLAG)]
		)

	# ------------------------------------------------- the REAL autoload
	# Not a director this file installed: `/root/Audio`, exactly as
	# `project.godot` registers it. A preview switch that is off in a fixture but
	# on in the autoload would be invisible to any test that builds its own.
	_director = root.get_node_or_null("Audio")
	if _director == null:
		return _die(
			"there is no /root/Audio autoload. This file must test the real one, not a copy."
		)
	print("   /root/Audio present, allow_unverified_music=%s"
			% str(_director.allow_unverified_music))
	_check(not bool(_director.allow_unverified_music),
			"the /root/Audio autoload booted with allow_unverified_music true although nothing "
			+ "armed the override. Nothing committed to this repository may turn unverified "
			+ "music on.")
	_director.track_unavailable.connect(
			func(track_id: String, reason: String) -> void: _reasons[track_id] = reason)
	_director.track_started.connect(
			func(track_id: String) -> void: _started.append(track_id))
	_director.unverified_music_allowed.connect(
			func(track_id: String, _reason: String) -> void:
				_fail.append("unverified_music_allowed fired for '%s' in a normal build" % track_id))

	# ------------------------------------------------- the PENDING fixture
	# Since 2026-09-20 the SHIPPED manifest is cleared (owner confirmation, see
	# docs/licences/music/). The silent path still has to work for the next
	# unverified delivery, so this file now proves it on a fixture that is the
	# pre-clearance manifest verbatim: the same two real files, paperwork pending.
	var fixture: RefCounted = (load(MANIFEST_SCRIPT) as GDScript).new()
	if not bool(fixture.load_file(PENDING_FIXTURE)):
		return _die("cannot load the pending fixture %s: %s" % [PENDING_FIXTURE, str(fixture.errors())])
	_director.set_manifest(fixture)
	print("1b. director now holds the PENDING fixture manifest %s" % PENDING_FIXTURE)
	var catalogue: Object = _director.manifest()
	_check((catalogue.errors() as Array).is_empty(),
			"the manifest reported schema errors: %s" % str(catalogue.errors()))

	# ------------------------------------------------- 2. THE FILES ARE REALLY THERE
	# The silence must not be a missing file wearing a licence problem's clothes.
	# Each track is decoded independently of the director -- the director is never
	# asked for a stream, because asking would be the one thing this file must not
	# do -- and checked against the duration recorded when the file was encoded.
	_check((catalogue.missing_track_ids() as Array).is_empty(),
			"a delivered track has no file on disk: %s" % str(catalogue.missing_track_ids()))
	for track_id: String in [MENU_TRACK, MISSION_TRACK]:
		var resolved: String = String(catalogue.resolved_path(track_id))
		var expected: float = float(
				(catalogue.get_track(track_id) as Dictionary).get("runtimeDurationSeconds", 0.0))
		if resolved.is_empty():
			_fail.append("%s resolves to no file at all" % track_id)
			continue
		var stream: AudioStream = AudioStreamOggVorbis.load_from_file(resolved)
		var length: float = stream.get_length() if stream != null else -1.0
		print("2. %s -> %s  present=%s  imported=%s  decodes=%s  %.2f s (manifest %.2f s)"
				% [track_id, resolved, str(FileAccess.file_exists(resolved)),
					str(ResourceLoader.exists(resolved)), str(stream != null), length, expected])
		_check(FileAccess.file_exists(resolved),
				"%s: %s is not on disk" % [track_id, resolved])
		_check(stream != null,
				("%s: %s is on disk but will not decode. A silent build must be silent because of "
				+ "the paperwork, never because the audio is broken.") % [track_id, resolved])
		_check(expected > 0.0 and absf(length - expected) < 0.2,
				"%s: the file decodes to %.2f s but the manifest recorded %.2f s"
						% [track_id, length, expected])

	# ------------------------------------------------- 3. THE GATE REFUSES, FOR THE PAPERWORK
	for track_id: String in [MENU_TRACK, MISSION_TRACK]:
		var reason: String = String(catalogue.refusal_reason(track_id))
		var row: Dictionary = catalogue.get_track(track_id)
		print("3. %s: commercialUse=%s licenseEvidence=%s -> is_playable=%s refusal=%s"
				% [track_id, str(row.get("commercialUse", "")), str(row.get("licenseEvidence", "")),
					str(catalogue.is_playable(track_id)), reason])
		_check(not bool(catalogue.is_playable(track_id)),
				"%s is playable, yet its licence evidence has not been supplied" % track_id)
		_check(reason == EXPECTED_REFUSAL,
				("%s is refused for '%s'; expected '%s'. The silence must be the licence gate, not "
				+ "a missing or misnamed file.") % [track_id, reason, EXPECTED_REFUSAL])
		_check(not bool(_director.may_play(track_id)),
				"the director would play '%s' with the override disarmed" % track_id)
	_check((catalogue.licence_refused_track_ids() as Array).size() == 2,
			"expected both tracks to be licence-refused, got %s"
					% str(catalogue.licence_refused_track_ids()))
	_check(bool(_director.is_silent_build()),
			"is_silent_build() is false, yet no track has licence evidence")
	_check((_director.overridden_track_ids() as Array).is_empty(),
			"overridden_track_ids() is not empty in a normal build: %s"
					% str(_director.overridden_track_ids()))

	# ------------------------------------------------- 4. THE REAL MENU, SILENT
	var save: Node = root.get_node_or_null("SaveService")
	if save == null or not save.has_method("reset_profile"):
		return _die("no SaveService; a real boot cannot be reproduced without one")
	save.call("reset_profile")
	# Not a first launch: main.gd auto-enters the house 1.4 s into a first run, and
	# this phase is about the menu.
	save.call("mark_level_completed", MISSION)

	var menu_packed: PackedScene = load(MENU_SCENE)
	if menu_packed == null:
		return _die("%s will not load" % MENU_SCENE)
	var menu: Node = menu_packed.instantiate()
	root.add_child(menu)
	current_scene = menu
	await _settle(0.6)
	_director.finish_fades()

	print("4. %s in the tree -> state '%s', wants '%s', playing '%s'"
			% [MENU_SCENE.get_file(), String(_director.current_state()),
				String(_director.desired_track_id()), String(_director.current_track_id())])
	_check(String(_director.current_state()) == "menu",
			"the real menu scene did not put the music in 'menu'; got '%s'"
					% String(_director.current_state()))
	_assert_silent("the menu")

	menu.queue_free()
	await process_frame

	# ------------------------------------------------- 5. THE REAL HOUSE + MISSION, SILENT
	save.call("reset_profile")
	var house_packed: PackedScene = load(HOUSE_SCENE)
	if house_packed == null:
		return _die("%s will not load" % HOUSE_SCENE)
	var world: Node = house_packed.instantiate()
	root.add_child(world)
	current_scene = world
	await process_frame
	await process_frame
	print("5. %s in the tree -> state '%s'"
			% [HOUSE_SCENE.get_file(), String(_director.current_state())])
	_check(String(_director.current_state()) == "house",
			"entering the house did not put the music in 'house'; got '%s'"
					% String(_director.current_state()))
	_assert_silent("the house")

	var level_director: Node = world.call("ensure_level_director")
	if level_director == null:
		return _die("no level director")
	level_director.call("start")
	await _settle(1.0)
	_director.finish_fades()

	var mission_id: String = String(level_director.call("get_mission_id")) \
			if level_director.has_method("get_mission_id") else ""
	print("6. mission '%s' running -> state '%s'"
			% [mission_id, String(_director.current_state())])
	_check(mission_id == MISSION,
			"a fresh profile opened '%s'; expected '%s'. The game must be fully playable silent."
					% [mission_id, MISSION])
	_check(String(_director.current_state()) == "miniGame",
			"the running mission did not put the music in 'miniGame'; got '%s'"
					% String(_director.current_state()))
	_assert_silent("the milk mission")

	# The game keeps working while it is quiet: walk the rooms the mission walks.
	var transition: Node = world.call("get_transition_controller") \
			if world.has_method("get_transition_controller") else null
	var rooms_walked: int = 0
	for room_id: String in ["kitchen", "livingRoom", "bedroom", "kitchen"]:
		if transition != null and transition.has_method("request_transition"):
			if bool(transition.call("request_transition", room_id, "default")):
				rooms_walked += 1
		await _settle(0.3)
	print("7. %d room transitions completed while silent" % rooms_walked)
	_check(rooms_walked == 4,
			"only %d of 4 room transitions worked; a silent build must still be a whole game"
					% rooms_walked)
	_assert_silent("four room transitions later")

	# ------------------------------------------------- 6. SPEECH AND SFX ARE UNAFFECTED
	# Music being silent must not be the whole sound system being silent: the
	# English prompt is the product.
	var sfx: Node = root.get_node_or_null("Sfx")
	var has_chime: bool = sfx != null and sfx.has_method("has_sfx") \
			and bool(sfx.call("has_sfx", "star_earned"))
	var tts: Node = root.get_node_or_null("TtsService")
	var spoke: bool = false
	if tts != null and tts.has_method("speak"):
		tts.call("speak", "Can you say milk?")
		await _settle(0.4)
		spoke = bool(tts.call("is_speaking"))
	print("8. sound is alive: Sfx 'star_earned' available=%s, TtsService speaking=%s"
			% [str(has_chime), str(spoke)])
	_check(has_chime,
			"the Sfx autoload has no 'star_earned' effect; the silence is not music-only")
	_check(spoke,
			"TtsService did not speak; a silent-music build must still say the English word")
	_assert_silent("while speaking")

	# ------------------------------------------------- what the build reported
	print("9. track_unavailable reasons: %s" % str(_reasons))
	_check(not _reasons.is_empty(),
			"the director never reported a refusal, so a diagnostics panel would show nothing")
	for track_id: Variant in _reasons.keys():
		_check(String(_reasons[track_id]) == EXPECTED_REFUSAL,
				"'%s' was reported unavailable for '%s'; expected '%s'"
						% [String(track_id), String(_reasons[track_id]), EXPECTED_REFUSAL])
	_check(_started.is_empty(),
			"track_started fired for %s in a normal build" % str(_started))

	world.queue_free()
	await process_frame
	_report()


# -----------------------------------------------------------------------------
# Reading the live audio
# -----------------------------------------------------------------------------


## The assertion this whole file is built around: not "the director thinks it is
## quiet" but "no AudioStreamPlayer in the tree is holding a piece of music".
func _assert_silent(where: String) -> void:
	_check(not bool(_director.is_playing_music()),
			"%s: the director is playing '%s' with the override disarmed"
					% [where, String(_director.current_track_id())])
	_check(String(_director.current_track_id()).is_empty(),
			"%s: a track id is assigned ('%s')" % [where, String(_director.current_track_id())])
	var players: Array = _music_players(root)
	if not players.is_empty():
		var described: Array = []
		for player: AudioStreamPlayer in players:
			described.append("%s (%.1f s, playing=%s)"
					% [String(player.get_path()), player.stream.get_length(), str(player.playing)])
		_fail.append(
			("%s: %d AudioStreamPlayer(s) hold a music stream in a normal build -- %s. Unverified "
			+ "music reached a player.") % [where, players.size(), ", ".join(described)]
		)
	for index: int in range(2):
		var voice: AudioStreamPlayer = _director.voice_player(index)
		if voice == null:
			continue
		_check(voice.stream == null,
				"%s: music voice %d still holds a stream" % [where, index])
		_check(not voice.playing, "%s: music voice %d is playing" % [where, index])


## Every `AudioStreamPlayer` anywhere in the tree that is holding a music stream.
## Music streams are told apart from the SFX player's by being long: no effect in
## this game reaches five seconds, and no track is shorter than a minute.
func _music_players(node: Node) -> Array:
	var found: Array = []
	if node is AudioStreamPlayer:
		var player: AudioStreamPlayer = node as AudioStreamPlayer
		if player.stream != null and player.stream.get_length() > 5.0:
			found.append(player)
	for child: Node in node.get_children():
		found.append_array(_music_players(child))
	return found


# -----------------------------------------------------------------------------
# Harness
# -----------------------------------------------------------------------------


## Lets REAL time pass. Fades, ducks and the production code's own gap timers are
## all wall-clock, so a frame count would expire before any of them.
func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail.append(message)


func _die(message: String) -> void:
	print("SMOKE FAIL: %s" % message)
	quit(1)


func _report() -> void:
	print("")
	if _fail.is_empty():
		print("SMOKE PASS -- a normal build plays NO music: both files are present and")
		print("              decodable, the licence gate refuses them for the paperwork,")
		print("              no AudioStreamPlayer ever holds a track, and the mission,")
		print("              the room transitions, the effects and the English all work.")
		quit(0)
	else:
		print("SMOKE FAIL -- %d problem(s):" % _fail.size())
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)
