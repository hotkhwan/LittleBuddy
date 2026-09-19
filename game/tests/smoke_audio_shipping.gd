extends SceneTree

## Music proven in the REAL game, from the real scenes.
##
##   Godot --headless --path game --script res://tests/smoke_audio_shipping.gd
##
## Not a unit test and deliberately not in `tests/cases/`: it installs
## `AudioDirector` exactly where the `Audio` autoload puts it, then instantiates
## `scenes/main/main.tscn` and `scenes/house/house_world.tscn` and asserts that the
## real `AudioStreamPlayer` behind the director is holding the real Ogg stream and
## is playing.
##
## The rule it exists to enforce: **"the .ogg file exists" is not evidence.** Every
## assertion below reads the live `AudioStreamPlayer` -- its `stream`, its
## `resource_path`, its `playing` flag and its `get_playback_position()` -- because
## a manifest can be right, a state machine can be right, and the child can still
## hear nothing.
##
## What a PASS means, and it is all checked below:
##   1. with the licence override DISARMED (the shipping default) nothing plays,
##      and that is quiet and errorless -- proven BEFORE anything else;
##   2. the real menu scene puts `littleDaysTheme` on a real stream player;
##   3. the real house + level director puts `hungryBunny` on one, in `miniGame`;
##   4. exactly ONE player in the whole tree holds music -- no overlap, ever;
##   5. objective changes and room transitions do NOT restart it: `track_started`
##      fires once and the playback position only ever moves forward;
##   6. real `TtsService.speak()` ducks the music, and finishing un-ducks it;
##   7. the two real tracks genuinely CROSSFADE -- both audible at once part-way
##      through, exactly one left when it settles;
##   8. mute silences it and unmuting brings the same track back;
##   9. both streams are configured to loop.

const DIRECTOR_SCRIPT: String = "res://scripts/audio/audio_director.gd"
const OVERRIDE_SCRIPT: String = "res://scripts/audio/music_licence_override.gd"
const MENU_SCENE: String = "res://scenes/main/main.tscn"
const HOUSE_SCENE: String = "res://scenes/house/house_world.tscn"

const MENU_TRACK: String = "littleDaysTheme"
const MISSION_TRACK: String = "hungryBunny"
const MISSION: String = "imHungry"

var _fail: Array = []
var _director: Node = null
var _started: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	print("=== proving music in the real game ===")
	# AFTER a frame: autoloads are not attached to `root` yet when a `--script`
	# SceneTree initialises. Same reason as smoke_mission01.gd.
	await process_frame

	# ---------------------------------------------------------------- the autoload
	# This is precisely what `Audio="*res://scripts/audio/audio_director.gd"` under
	# `[autoload]` does: one director, named, directly under /root, installed before
	# any scene. Adding the line to project.godot makes the rest of this file the
	# game's real boot path rather than a simulation of it.
	# ADOPT the real autoload if it is there, and only install one if it is not.
	#
	# This file predates the `Audio` autoload existing. It always installed its
	# own director named "Audio" -- and once project.godot registered the real
	# one, `add_child()` found the name taken, renamed the copy to `@Node@2`, and
	# TWO directors ran at once. With `-- --allow-unverified-music` the flag armed
	# both and every track played doubled, so the command printed in the audio
	# docs failed if you followed it literally. Without the flag only this
	# script's copy was armed and the autoload stayed silent, which is exactly why
	# it went unnoticed.
	_director = root.get_node_or_null("Audio")
	if _director != null:
		print("0. adopted the real /root/Audio autoload (%s)" % _director.get_class())
	else:
		var director_script: GDScript = load(DIRECTOR_SCRIPT) as GDScript
		if director_script == null:
			return _die("cannot load %s" % DIRECTOR_SCRIPT)
		_director = director_script.new()
		_director.name = "Audio"
		root.add_child(_director)
		await process_frame
		print("0. installed /root/Audio (%s) -- no autoload present" % _director.get_class())

	var binder: Node = _director.binder()
	_check(binder != null,
			"the director created no MusicBinder when installed as an autoload; nothing would "
			+ "ever follow the game")
	_director.track_started.connect(func(track_id: String) -> void: _started.append(track_id))

	# ------------------------------------------------- 1. the SHIPPING default
	# Proven first, and proven on this same director, so that everything after it is
	# visibly a deliberate departure from the default rather than the default.
	var override: GDScript = load(OVERRIDE_SCRIPT) as GDScript
	var armed_by_operator: bool = bool(override.is_armed())
	print("1. licence override: %s" % String(override.describe()))
	# Forced off for this phase rather than merely asserted off, because this file is
	# ALSO the documented way to arm the override (`-- --allow-unverified-music`), and
	# an operator who armed it must still see the shipping default proven. That the
	# default is disarmed when nobody armed it is asserted in the unit suite instead,
	# where no flag is ever passed: test_audio_music_binder.gd.
	if not armed_by_operator:
		_check(not bool(_director.allow_unverified_music),
				"allow_unverified_music is armed although nothing armed it. Nothing committed "
				+ "to this repository may turn unverified music on.")
	_director.allow_unverified_music = false
	for state: String in ["menu", "house", "miniGame", "reward"]:
		_director.set_state(state)
		_director.finish_fades()
		_check(not bool(_director.is_playing_music()),
				("state '%s' played music with the licence override disarmed. Unverified tracks "
				+ "must be silent in every build.") % state)
	_check(bool(_director.is_silent_build()),
			"is_silent_build() is false with the override disarmed, yet no track has licence "
			+ "evidence")
	_check(_director.manifest().missing_track_ids().is_empty(),
			"a delivered track has no file on disk: %s"
					% str(_director.manifest().missing_track_ids()))
	print("   shipping default: silent in every state, both .ogg files present, 0 errors")
	_director.set_state("silent")
	_director.finish_fades()

	# ------------------------------------------------- arm the preview, loudly
	# Equivalent to `-- --allow-unverified-music`. Done in the open, and only after
	# the silent default above has been proven, because the point of the rest of
	# this run is the AUDIO PIPELINE and not the paperwork.
	_director.allow_unverified_music = true
	print("2. licence override ARMED (%s)."
			% ("by the operator, on the command line or via the marker file"
				if armed_by_operator else "by this script; same effect as `-- %s`"
						% String(override.CLI_FLAG)))
	print("   The manifest still says commercialUse=\"pending\" and the gate still")
	print("   refuses: MusicManifest.is_playable() is %s for both tracks."
			% str(_director.manifest().is_playable(MENU_TRACK)))
	print("   Overridden tracks: %s" % str(_director.overridden_track_ids()))
	_check(not bool(_director.manifest().is_playable(MENU_TRACK)),
			"arming the override changed MusicManifest.is_playable(). The gate must never soften.")
	_check(_director.overridden_track_ids().size() == 2,
			"expected both tracks to be override-only, got %s"
					% str(_director.overridden_track_ids()))

	# ------------------------------------------------- 3. THE REAL MENU SCENE
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

	print("3. %s in the tree -> state '%s', track '%s'"
			% [MENU_SCENE.get_file(), String(_director.current_state()),
				String(_director.current_track_id())])
	_check(String(_director.current_state()) == "menu",
			"the real menu scene did not put the music in 'menu'; got '%s'"
					% String(_director.current_state()))
	_assert_really_playing(MENU_TRACK, "little_days_theme.ogg", "the menu")

	menu.queue_free()
	await process_frame

	# ------------------------------------------------- 4. THE REAL HOUSE + MISSION
	save.call("reset_profile")
	for level_id: Variant in _levels_before(MISSION):
		save.call("mark_level_completed", String(level_id))

	var house_packed: PackedScene = load(HOUSE_SCENE)
	if house_packed == null:
		return _die("%s will not load" % HOUSE_SCENE)
	var world: Node = house_packed.instantiate()
	root.add_child(world)
	current_scene = world
	await process_frame
	await process_frame
	print("4. %s in the tree -> state '%s'"
			% [HOUSE_SCENE.get_file(), String(_director.current_state())])
	_check(String(_director.current_state()) == "house",
			"entering the house did not put the music in 'house'; got '%s'"
					% String(_director.current_state()))

	var level_director: Node = world.call("ensure_level_director")
	if level_director == null:
		return _die("no level director")
	level_director.call("start")
	await _settle(1.0)

	var mission_id: String = String(level_director.call("get_mission_id")) \
			if level_director.has_method("get_mission_id") else ""
	print("5. mission '%s' running -> state '%s', track '%s'"
			% [mission_id, String(_director.current_state()),
				String(_director.current_track_id())])
	_check(mission_id == MISSION,
			"a fresh profile opened '%s'; expected '%s'" % [mission_id, MISSION])
	_check(String(_director.current_state()) == "miniGame",
			"the running mission did not put the music in 'miniGame'; got '%s'"
					% String(_director.current_state()))
	_director.finish_fades()
	_assert_really_playing(MISSION_TRACK, "hungry_bunny.ogg", "the milk mission")

	# ------------------------------------------------- 5. EXACTLY ONE PLAYER
	var players: Array = _music_players(root)
	print("6. AudioStreamPlayers holding a music stream, whole tree: %d" % players.size())
	for player: AudioStreamPlayer in players:
		print("   %s  %s %.2f s  playing=%s  volume=%.1f dB"
				% [String(player.get_path()), player.stream.get_class(),
					player.stream.get_length(), str(player.playing), player.volume_db])
	_check(players.size() == 1,
			"%d players hold a music stream. Exactly one piece of music may sound at a time."
					% players.size())

	# ------------------------------------------------- 6. NO RESTART ON CHANGES
	# The two events that happen most often in a mission. Neither may restart the
	# music, and the proof is the playback clock: it only ever goes forward.
	var before_position: float = _position()
	var starts_before: int = _started.count(MISSION_TRACK)
	var transition: Node = world.call("get_transition_controller") \
			if world.has_method("get_transition_controller") else null
	var rooms_walked: int = 0
	for room_id: String in ["kitchen", "livingRoom", "bedroom", "kitchen"]:
		if transition != null and transition.has_method("request_transition"):
			if bool(transition.call("request_transition", room_id, "default")):
				rooms_walked += 1
		await _settle(0.35)
	var after_position: float = _position()
	print("7. %d room transitions later: track '%s', position %.2f s -> %.2f s, "
			% [rooms_walked, String(_director.current_track_id()),
				before_position, after_position]
			+ "track_started fired %d time(s)" % _started.count(MISSION_TRACK))
	_check(String(_director.current_track_id()) == MISSION_TRACK,
			"a room transition changed the mission's track to '%s'"
					% String(_director.current_track_id()))
	_check(_started.count(MISSION_TRACK) == starts_before,
			"track_started fired again during room transitions (%d -> %d): the music restarted"
					% [starts_before, _started.count(MISSION_TRACK)])
	_check(after_position >= before_position,
			"the playback position went backwards (%.2f -> %.2f): the track restarted"
					% [before_position, after_position])
	_check(_music_players(root).size() == 1,
			"more than one music player after four room transitions")

	# ------------------------------------------------- 7. SPEECH DUCKING
	# The baseline has to be measured while the game is QUIET, and during a mission
	# it usually is not: the runner speaks a prompt for every beat, so the first
	# reading taken here was already ducked and the "duck" looked like a no-op. Wait
	# for real silence first -- which is itself proof that the duck releases.
	var tts: Node = root.get_node_or_null("TtsService")
	if tts == null or not tts.has_method("speak"):
		_fail.append("no TtsService; ducking cannot be proven")
	else:
		var went_quiet: bool = await _wait_for_quiet(tts, 12.0)
		var open_db: float = _volume_db()
		print("8. quiet again after %s: music %.1f dB, ducked=%s, duck gain %.3f"
				% [str(went_quiet), open_db, str(_director.is_ducked()),
					float(_director.duck_gain())])
		_check(went_quiet,
				"TtsService never stopped speaking within 12 s, so the duck could not be "
				+ "measured against a quiet baseline")
		_check(not bool(_director.is_ducked()),
				"the duck is still held with nothing speaking and nothing listening: it stuck")
		_check(is_equal_approx(float(_director.duck_gain()), 1.0),
				"the duck gain settled at %.3f instead of 1.0 with nothing speaking"
						% float(_director.duck_gain()))

		tts.call("speak", "Can you say milk?")
		await _settle(0.5)
		var speaking: bool = bool(tts.call("is_speaking"))
		var ducked_db: float = _volume_db()
		print("   speaking -> music %.1f dB (duck gain %.3f), still playing=%s"
				% [ducked_db, float(_director.duck_gain()),
					str(_director.is_playing_music())])
		_check(speaking, "TtsService reported it was not speaking; ducking cannot be judged")
		_check(bool(_director.is_ducked()),
				"the director is not ducked while TtsService is speaking; the child would be "
				+ "trying to hear 'milk' over the music")
		_check(ducked_db < open_db - 6.0,
				("music only moved %.1f dB while speaking (%.1f -> %.1f). It must get out of the "
				+ "way of English.") % [open_db - ducked_db, open_db, ducked_db])
		_check(bool(_director.is_playing_music()),
				"ducking stopped the music instead of lowering it")
		_check(_music_players(root).size() == 1,
				"ducking changed how many players hold music")

		var released: bool = await _wait_for_quiet(tts, 12.0)
		await _settle(1.0)
		var restored_db: float = _volume_db()
		print("   speech over (%s) -> music back to %.1f dB (duck gain %.3f)"
				% [str(released), restored_db, float(_director.duck_gain())])
		_check(released, "TtsService never finished the prompt this test asked for")
		_check(not bool(_director.is_ducked()), "the duck stuck after speech finished")
		_check(absf(restored_db - open_db) < 0.5,
				"music came back to %.1f dB instead of %.1f dB" % [restored_db, open_db])

	# ------------------------------------------------- 8. A REAL CROSSFADE
	# The two delivered tracks never meet on the game's own route (the house sits
	# between the menu and a mission and has no track of its own), so the crossfade
	# between them is driven directly here. It has to be checked on the real streams:
	# a hard cut is a transient, and a transient is the one thing a 4-year-old
	# holding an iPad 30 cm from their face must never be given.
	_director.set_state("silent")
	_director.finish_fades()
	_director.set_state("menu")
	_director.finish_fades()
	var outgoing_before: float = _volume_db()
	_director.set_state("miniGame")
	_director.advance(0.25)  # part-way into miniGame's 0.8 s fade
	var live: Array = []
	for index: int in range(2):
		var voice: AudioStreamPlayer = _director.voice_player(index)
		if voice != null and voice.stream != null:
			live.append("%s @ %.1f dB" % [String(_director.voice_track_id(index)), voice.volume_db])
	print("9. mid-crossfade menu -> miniGame: %s (fading=%s)"
			% [str(live), str(_director.is_fading())])
	_check(live.size() == 2,
			("only %d voice(s) held a stream mid-crossfade. Both tracks must overlap, or the "
			+ "transition is a cut with a gap in it.") % live.size())
	_check(bool(_director.is_fading()), "no fade was running 0.25 s into a 0.8 s crossfade")
	_check(_volume_db() < outgoing_before,
			"the incoming track was already at full level 0.25 s in; that is a hard cut")
	_director.finish_fades()
	print("   settled -> track '%s', players holding music=%d, %.1f dB"
			% [String(_director.current_track_id()), _music_players(root).size(), _volume_db()])
	_check(String(_director.current_track_id()) == MISSION_TRACK,
			"the crossfade landed on '%s'" % String(_director.current_track_id()))
	_check(_music_players(root).size() == 1,
			("%d players still hold music after the crossfade settled; the outgoing track was "
			+ "never released") % _music_players(root).size())

	# ------------------------------------------------- 9. MUTE
	_director.set_muted(true)
	_director.finish_fades()
	print("10. muted -> playing=%s, players holding music=%d"
			% [str(_director.is_playing_music()), _music_players(root).size()])
	_check(not bool(_director.is_playing_music()), "mute left music playing")
	_director.set_muted(false)
	await _settle(1.5)
	_director.finish_fades()
	print("   unmuted -> track '%s', %.1f dB"
			% [String(_director.current_track_id()), _volume_db()])
	_check(String(_director.current_track_id()) == MISSION_TRACK,
			"unmuting did not bring back the mission's track; got '%s'"
					% String(_director.current_track_id()))

	# ------------------------------------------------- 9. LOOPING
	for track_id: String in [MENU_TRACK, MISSION_TRACK]:
		var stream: AudioStream = _director._stream_for(track_id)
		_check(stream != null, "no stream resolves for %s" % track_id)
		if stream == null:
			continue
		var loops: bool = bool(stream.get("loop")) if "loop" in stream else false
		print("11. %s: %s, loop=%s, length=%.2f s"
				% [track_id, stream.get_class(), str(loops), stream.get_length()])
		_check(loops, "%s is not set to loop; the music would stop dead after one play" % track_id)

	world.queue_free()
	await process_frame
	_report()


# -----------------------------------------------------------------------------
# Reading the live audio
# -----------------------------------------------------------------------------


## The whole point of this file. Asserts against the `AudioStreamPlayer` the engine
## is actually holding, not against the director's opinion of itself.
func _assert_really_playing(track_id: String, file_name: String, where: String) -> void:
	_check(String(_director.current_track_id()) == track_id,
			"%s wanted '%s' but the director is on '%s'"
					% [where, track_id, String(_director.current_track_id())])
	var resolved: String = String(_director.manifest().resolved_path(track_id))
	_check(resolved.get_file() == file_name,
			"%s: the manifest resolves '%s' to '%s'; expected '%s'"
					% [where, track_id, resolved, file_name])
	var player: AudioStreamPlayer = _active_player()
	if player == null:
		_fail.append("%s: no AudioStreamPlayer holds a stream at all" % where)
		return
	if player.stream == null:
		_fail.append("%s: the active voice has no stream" % where)
		return
	# `resource_path` is EMPTY on purpose: the director duplicates the imported
	# resource before applying loop points, so it cannot leak them into anything
	# else that loads the same file, and a duplicate carries no path. So the stream
	# is identified by its LENGTH against the duration the manifest recorded when
	# the file was encoded -- 92.72 s and 64.40 s are not values a wrong file has.
	var expected: float = float(
			_director.manifest().get_track(track_id).get("runtimeDurationSeconds", 0.0))
	print("   live player: %s  class=%s  from=%s  imported=%s  playing=%s  %.1f dB  pos=%.2f s  length=%.2f s"
			% [String(player.get_path()), player.stream.get_class(), resolved.get_file(),
				str(ResourceLoader.exists(resolved)), str(player.playing), player.volume_db,
				player.get_playback_position(), player.stream.get_length()])
	_check(player.playing,
			"%s: the AudioStreamPlayer is not playing. Nothing would come out of the iPad."
					% where)
	_check(player.volume_db > _director.OFF_DB + 1.0,
			"%s: the player is at %.1f dB, which is inaudible" % [where, player.volume_db])
	_check(expected > 0.0 and absf(player.stream.get_length() - expected) < 0.2,
			("%s: the live stream is %.2f s long but the manifest recorded %.2f s for '%s'. "
			+ "That is a different file.")
					% [where, player.stream.get_length(), expected, track_id])


## The director's currently active voice.
func _active_player() -> AudioStreamPlayer:
	for index: int in range(2):
		var player: AudioStreamPlayer = _director.voice_player(index)
		if player != null and player.stream != null \
				and String(_director.voice_track_id(index)) == String(_director.current_track_id()):
			return player
	return null


func _volume_db() -> float:
	var player: AudioStreamPlayer = _active_player()
	return player.volume_db if player != null else _director.OFF_DB


func _position() -> float:
	var player: AudioStreamPlayer = _active_player()
	return player.get_playback_position() if player != null else -1.0


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


## The chain levels before `level_id`, from content. Same helper as
## smoke_mission01.gd, for the same reason: to reach a mission that is not first.
func _levels_before(level_id: String) -> Array:
	var library: Object = load("res://scripts/content/content_library.gd").new()
	library.call("load_all")
	var system: Object = load("res://scripts/progression/level_system.gd").new()
	system.call("load_all", library)
	var before: Array = []
	for chained: String in (system.call("get_chapter_chain", "ch3") as PackedStringArray):
		if chained == level_id:
			return before
		before.append(chained)
	return []


## Waits until nothing is speaking and nothing is listening, so a duck measurement
## has a real baseline. Returns false on timeout rather than hanging.
func _wait_for_quiet(tts: Node, seconds: float) -> bool:
	var speech: Node = root.get_node_or_null("SpeechService")
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var busy: bool = tts != null and tts.has_method("is_speaking") \
				and bool(tts.call("is_speaking"))
		if not busy and speech != null and speech.has_method("is_listening"):
			busy = bool(speech.call("is_listening"))
		if not busy and not bool(_director.is_ducked()) \
				and is_equal_approx(float(_director.duck_gain()), 1.0):
			return true
	return false


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
		print("SMOKE PASS -- both delivered tracks play in the real game, one at a time,")
		print("              they duck for English, and the shipping default is still silent")
		print("              because no licence evidence has been supplied.")
		quit(0)
	else:
		print("SMOKE FAIL -- %d problem(s):" % _fail.size())
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)
