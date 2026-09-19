extends RefCounted
## The audio manager: BGM states, crossfades, the mixer, mute -- and, above all,
## what happens when there is no music at all.
##
## ## The headline assertion is the silent one
##
## This repository ships with **zero music files**. The tracks are listed in the
## manifest before they exist so that a delivery is a file drop rather than a code
## change, which means "no music" is not a temporary inconvenience -- it is the
## configuration the game ships in today and must remain completely normal.
## `_test_a_build_with_no_music_behaves_normally()` drives every state, every
## volume control and mute through a director with nothing to play and asserts
## that the API stays honest and quiet.
##
## ## Why fades are driven by hand
##
## The headless runner works inside `SceneTree._initialize()`, so the tree never
## iterates, `_process()` never fires and no audio can be mixed. `advance(delta)`
## exists for exactly that reason: the crossfade is real logic and is tested as
## logic, with the engine's mixer out of the picture.
##
## ## The fixture uses one of our own SFX files as a stand-in "track"
##
## A crossfade cannot be observed without two streams, and this case must not add
## an audio file to the repository. `audio/sfx/*.wav` are synthesised by
## `tools/generate_sfx.gd`, so they are ours outright -- using two of them as
## fixture "music" adds no licence surface and creates nothing.

const DIRECTOR_SCRIPT: String = "res://scripts/audio/audio_director.gd"
const MANIFEST_SCRIPT: String = "res://scripts/audio/music_manifest.gd"
const MACHINE_SCRIPT: String = "res://scripts/audio/bgm_state_machine.gd"
const SFX_SCRIPT: String = "res://scripts/audio/sfx_player.gd"
const OVERRIDE_SCRIPT: String = "res://scripts/audio/music_licence_override.gd"
const SHIPPED_MANIFEST: String = "res://content/audio/manifest.json"

## Real files, ours, used as stand-in tracks. See the class docs.
const FIXTURE_FILE_A: String = "res://audio/sfx/bedtime_chime.wav"
const FIXTURE_FILE_B: String = "res://audio/sfx/room_change.wav"

const EVIDENCE: String = "test fixture: our own generated SFX; see docs/ASSET_MANIFEST.md"

var _director_script: GDScript = null
var _manifest_script: GDScript = null
var _machine_script: GDScript = null


func test_name() -> String:
	return "audio_director"


func _override_script() -> GDScript:
	return load(OVERRIDE_SCRIPT) as GDScript


func run():
	var failures: Array = []

	for path: String in [DIRECTOR_SCRIPT, MANIFEST_SCRIPT, MACHINE_SCRIPT]:
		var resource: Resource = load(path)
		if resource == null or not (resource is GDScript):
			failures.append("could not load %s" % path)
	if not failures.is_empty():
		return failures
	_director_script = load(DIRECTOR_SCRIPT) as GDScript
	_manifest_script = load(MANIFEST_SCRIPT) as GDScript
	_machine_script = load(MACHINE_SCRIPT) as GDScript

	failures.append_array(_test_a_build_with_no_music_behaves_normally())
	failures.append_array(_test_the_state_machine())
	failures.append_array(_test_no_transition_is_a_hard_cut())
	failures.append_array(_test_a_refused_track_is_never_assigned_a_stream())
	failures.append_array(_test_a_cleared_track_plays_and_crossfades())
	failures.append_array(_test_volume_controls())
	failures.append_array(_test_mute())
	failures.append_array(_test_sfx_player_binding())

	return failures


# -----------------------------------------------------------------------------
# 1. Silent-safe
# -----------------------------------------------------------------------------


## The shipped condition of this build. Nothing here may error, warn repeatedly,
## or lie about what is playing.
func _test_a_build_with_no_music_behaves_normally():
	var failures: Array = []

	var director: Node = _director_script.new()
	# The decision is asserted below; the engine warning itself would only make the
	# suite output noisy. See `warn_on_licence_refusal`.
	director.warn_on_licence_refusal = false
	var unavailable: Array = []
	director.track_unavailable.connect(
		func(track_id: String, reason: String) -> void:
			unavailable.append("%s:%s" % [track_id, reason])
	)
	var states_seen: Array = []
	director.music_state_changed.connect(
		func(state: String) -> void: states_seen.append(state)
	)

	if director.allow_unverified_music:
		failures.append(
			("allow_unverified_music is armed inside the test suite. It must be false unless a "
			+ "human passed %s or created %s -- see music_licence_override.gd.")
			% [_override_script().CLI_FLAG, _override_script().MARKER_PATH]
		)
	if not director.is_silent_build():
		failures.append(
			("is_silent_build() is false. The two delivered tracks are still refused (rights "
			+ "unrecorded), so the shipping build is silent. If that changes -- real licence "
			+ "evidence, `commercialUse: \"verified\"` -- update this case alongside it, but the "
			+ "silent path must keep a test: a build with no playable music is supported forever.")
		)
	if director.manifest() == null:
		failures.append("manifest() must never return null, even with no manifest on disk")

	# Every state, twice, plus nonsense, plus a return -- nothing may throw and
	# nothing may claim to be playing.
	var all_states: Array = [
		director.STATE_MENU,
		director.STATE_HOUSE,
		director.STATE_MINI_GAME,
		director.STATE_REWARD,
		director.STATE_SILENT,
		director.STATE_HOUSE,
		"parentSettings",
		"",
	]
	for state: String in all_states:
		var playing: bool = director.set_state(state)
		if playing:
			failures.append("set_state(%s) reported music playing in a build with no music" % state)
		if not director.current_track_id().is_empty():
			failures.append("state %s assigned a track id with no music present" % state)
		if director.is_playing_music():
			failures.append("is_playing_music() is true with no music present")
		director.advance(0.5)

	if states_seen.is_empty():
		failures.append(
			"no music_state_changed signal was emitted. A silent build must still report where "
			+ "the music WOULD be, or nothing can be diagnosed and nothing can be wired up later."
		)
	if states_seen.has("parentSettings") or states_seen.has(""):
		failures.append("an unknown state name must not be reported as a state change")

	# The manifest's own tracks must be reported unavailable, once each -- a
	# diagnostics panel needs the fact, and nobody needs it per frame.
	var first_report_count: int = unavailable.size()
	director.set_state(director.STATE_SILENT)
	director.set_state(director.STATE_MENU)
	director.set_state(director.STATE_SILENT)
	director.set_state(director.STATE_MENU)
	if unavailable.size() != first_report_count:
		failures.append(
			("track_unavailable fired again for a track already reported (%d -> %d). The missing "
			+ "file is the normal state of this build; repeating the report per transition is the "
			+ "warning spam this design exists to avoid.")
			% [first_report_count, unavailable.size()]
		)

	# WHY the build is silent decides whether a developer is told about it, and the
	# two reasons are opposites:
	#
	#   no file yet      -> the designed state before a delivery. Say nothing; a
	#                       boot-time warning for the normal case teaches people to
	#                       ignore warnings.
	#   file, no licence -> a delivery landed and nobody recorded its rights. That
	#                       is the one audio mistake that could reach a shipped
	#                       build, so warn, once.
	#
	# Since 2026-09-19 this repository is in the SECOND state: `audio/music/*.ogg`
	# exist and their rows say commercialUse "pending". So the warning is now
	# expected, and what is asserted is that it tracks the file's presence rather
	# than firing or staying quiet unconditionally.
	for track_id: String in director.manifest().track_ids():
		var reason: String = director.manifest().refusal_reason(track_id)
		var has_file: bool = not director.manifest().resolved_path(track_id).is_empty()
		var wants_to_warn: bool = director.should_warn_about(track_id, reason)
		if has_file and not wants_to_warn:
			failures.append(
				("there IS a file for %s and its licence is refused (%s), yet the director stays "
				+ "quiet. Unrecorded rights on a delivered track must be said out loud.")
				% [track_id, reason]
			)
		if not has_file and wants_to_warn:
			failures.append(
				("the director wants to warn about %s (%s) when no file for it exists. A boot-time "
				+ "warning for the designed state teaches people to ignore warnings.")
				% [track_id, reason]
			)

	# Volume and mute must work on a silent build, so a settings screen does not
	# need to know whether music exists.
	director.set_master_volume_db(-6.0)
	director.set_music_volume_db(-3.0)
	director.set_sfx_volume_db(-2.0)
	director.set_muted(true)
	director.set_muted(false)
	director.advance(1.0)
	director.play_sfx("gentle_tap")  # unbound: a no-op, not a crash
	director.stop_music()
	director.finish_fades()
	if director.is_playing_music():
		failures.append("stop_music() left music playing")
	if director.is_fading():
		failures.append("finish_fades() left a fade running")

	director.free()
	return failures


# -----------------------------------------------------------------------------
# 2. The state machine
# -----------------------------------------------------------------------------


func _test_the_state_machine():
	var failures: Array = []

	var machine: RefCounted = _machine_script.new()
	if machine.state() != _machine_script.STATE_SILENT:
		failures.append("a fresh machine must start silent")

	var changed: Dictionary = machine.request(_machine_script.STATE_MENU)
	if String(changed["outcome"]) != _machine_script.OUTCOME_CHANGED:
		failures.append("silent -> menu should be a change")
	if String(changed["from"]) != _machine_script.STATE_SILENT:
		failures.append("the transition must report where it came from")

	var repeated: Dictionary = machine.request(_machine_script.STATE_MENU)
	if String(repeated["outcome"]) != _machine_script.OUTCOME_SAME_STATE:
		failures.append("re-requesting the current state must be a no-op, not a restart")

	# A typo must not silence the game.
	var before: String = machine.state()
	var bogus: Dictionary = machine.request("livingRoomMusic")
	if String(bogus["outcome"]) != _machine_script.OUTCOME_UNKNOWN_STATE:
		failures.append("an unknown state must be reported as unknown")
	if machine.state() != before:
		failures.append(
			"an unknown state changed the machine. A typo in a caller must leave the music alone, "
			+ "not stop it."
		)

	# Reward is a visit: it must hand back what it interrupted.
	machine.request(_machine_script.STATE_HOUSE)
	machine.request(_machine_script.STATE_REWARD)
	if machine.previous_state() != _machine_script.STATE_HOUSE:
		failures.append("the machine must remember the state a celebration interrupted")
	machine.request_return()
	if machine.state() != _machine_script.STATE_HOUSE:
		failures.append("request_return() must go back to the interrupted state")

	machine.reset()
	if machine.state() != _machine_script.STATE_SILENT \
			or machine.previous_state() != _machine_script.STATE_SILENT:
		failures.append("reset() must clear both the state and the history")

	# The five states the rest of the game addresses by name.
	for state: String in ["silent", "menu", "house", "miniGame", "reward"]:
		if not _machine_script.is_known_state(state):
			failures.append("`%s` must be a known BGM state" % state)
	if _machine_script.STATES.size() != 5:
		failures.append("expected exactly 5 BGM states, found %d" % _machine_script.STATES.size())

	# The director must expose the same names, so no caller has to import the
	# machine to change the music.
	var director: Node = _director_script.new()
	for pair: Array in [
		[director.STATE_SILENT, _machine_script.STATE_SILENT],
		[director.STATE_MENU, _machine_script.STATE_MENU],
		[director.STATE_HOUSE, _machine_script.STATE_HOUSE],
		[director.STATE_MINI_GAME, _machine_script.STATE_MINI_GAME],
		[director.STATE_REWARD, _machine_script.STATE_REWARD],
	]:
		if String(pair[0]) != String(pair[1]):
			failures.append("the director's state constants have drifted from the machine's")
	director.free()

	return failures


## A hard cut is a transient, and a transient is the one thing a 4-year-old
## holding an iPad 30 cm from their face should never be given. The SFX in this
## project all have measured attack ramps for the same reason
## (`test_audio_assets.gd`); music transitions are held to it too.
func _test_no_transition_is_a_hard_cut():
	var failures: Array = []

	for state: String in _machine_script.STATES:
		var seconds: float = _machine_script.fade_seconds_to(state)
		if seconds < _machine_script.MIN_FADE_SECONDS:
			failures.append(
				"the fade into %s is %.2f s, below the %.2f s floor -- that is an audible cut"
				% [state, seconds, _machine_script.MIN_FADE_SECONDS]
			)
		if seconds > _machine_script.MAX_FADE_SECONDS:
			failures.append("the fade into %s is %.2f s, longer than any transition should be"
					% [state, seconds])

	if _machine_script.MIN_FADE_SECONDS <= 0.0:
		failures.append("MIN_FADE_SECONDS must be greater than zero or the floor means nothing")

	# An unlisted state still gets a fade rather than a cut.
	if _machine_script.fade_seconds_to("notAState") < _machine_script.MIN_FADE_SECONDS:
		failures.append("an unknown state must still fade, not cut")

	var director: Node = _director_script.new()
	if not director.crossfade_enabled:
		failures.append("crossfading must be ON by default")
	director.free()

	return failures


# -----------------------------------------------------------------------------
# 3. The licence gate, from the director's side
# -----------------------------------------------------------------------------


## The manifest owns the rule; this proves the director actually obeys it. The
## fixture's file genuinely exists, so the ONLY thing stopping playback is the
## paperwork.
func _test_a_refused_track_is_never_assigned_a_stream():
	var failures: Array = []

	for refused: Variant in [
		_manifest_script.COMMERCIAL_USE_PENDING,
		_manifest_script.COMMERCIAL_USE_DENIED,
		true,
		"Verified",
	]:
		var director: Node = _director_script.new()
		# The warning is asserted separately, via should_warn_about(); suppressed
		# here so a green suite stays free of noise.
		director.warn_on_licence_refusal = false
		var reasons: Array = []
		director.track_unavailable.connect(
			func(_id: String, reason: String) -> void: reasons.append(reason)
		)
		director.set_manifest(
			_manifest(
				[
					_track("fixtureTheme", FIXTURE_FILE_A, ["menu"], refused, EVIDENCE),
				]
			)
		)

		if director.set_state(director.STATE_MENU):
			failures.append(
				("the director played a track with commercialUse %s. The file exists, so the "
				+ "licence gate is the only thing between a child's device and music nobody has "
				+ "cleared for commercial use.") % JSON.stringify(refused)
			)
		if not director.current_track_id().is_empty():
			failures.append("a refused track was assigned to a voice")
		if director.voice_track_id(0) != "" or director.voice_track_id(1) != "":
			failures.append("a refused track reached an AudioStreamPlayer")
		if not reasons.has(_manifest_script.REFUSAL_COMMERCIAL_USE_UNVERIFIED):
			failures.append(
				"the refusal of commercialUse %s was not reported as `%s`, got %s"
				% [
					JSON.stringify(refused),
					_manifest_script.REFUSAL_COMMERCIAL_USE_UNVERIFIED,
					str(reasons),
				]
			)
		# ...and THIS is the case that deserves a developer's attention: the
		# paperwork is wrong and a file is sitting right there.
		if not director.should_warn_about(
			"fixtureTheme", _manifest_script.REFUSAL_COMMERCIAL_USE_UNVERIFIED
		):
			failures.append(
				"a present file with unverified rights must be warned about; that is somebody "
				+ "having dropped a delivery in without recording where it came from"
			)
		if not director.licence_refused_track_ids().has("fixtureTheme"):
			failures.append("a refused track must be listed by licence_refused_track_ids()")
		if not director.is_silent_build():
			failures.append("a build whose only track is refused is a silent build")
		director.free()

	# Evidence-free "verified" is refused by the director too.
	var evidence_free: Node = _director_script.new()
	evidence_free.warn_on_licence_refusal = false
	evidence_free.set_manifest(
		_manifest(
			[
				_track(
					"fixtureTheme",
					FIXTURE_FILE_A,
					["menu"],
					_manifest_script.COMMERCIAL_USE_VERIFIED,
					_manifest_script.EVIDENCE_PENDING
				),
			]
		)
	)
	if evidence_free.set_state(evidence_free.STATE_MENU):
		failures.append("a \"verified\" track with PENDING evidence was played")
	evidence_free.free()

	# Swapping a manifest in must re-evaluate: a cleared track that becomes
	# refused has to stop, not keep playing because it was cleared a moment ago.
	var swapped: Node = _director_script.new()
	swapped.warn_on_licence_refusal = false
	swapped.set_manifest(_manifest([_cleared_track("fixtureTheme", FIXTURE_FILE_A, ["menu"])]))
	swapped.set_state(swapped.STATE_MENU)
	swapped.finish_fades()
	if not swapped.is_playing_music():
		failures.append("the cleared control case did not play; the swap test would be vacuous")
	swapped.set_manifest(
		_manifest(
			[
				_track(
					"fixtureTheme",
					FIXTURE_FILE_A,
					["menu"],
					_manifest_script.COMMERCIAL_USE_DENIED,
					EVIDENCE
				),
			]
		)
	)
	swapped.finish_fades()
	if swapped.is_playing_music():
		failures.append(
			"a track kept playing after the manifest marked it denied; a rights withdrawal must "
			+ "take effect, not wait for the next scene change"
		)
	swapped.free()

	return failures


# -----------------------------------------------------------------------------
# 4. Playback and crossfade
# -----------------------------------------------------------------------------


func _test_a_cleared_track_plays_and_crossfades():
	var failures: Array = []

	if not FileAccess.file_exists(FIXTURE_FILE_A) or not FileAccess.file_exists(FIXTURE_FILE_B):
		return ["the fixture audio files are missing; the playback path cannot be tested"]

	var director: Node = _director_script.new()
	var started: Array = []
	director.track_started.connect(func(track_id: String) -> void: started.append(track_id))
	var stopped: Array = []
	director.music_stopped.connect(func() -> void: stopped.append(true))
	director.set_manifest(
		_manifest(
			[
				_cleared_track("menuTheme", FIXTURE_FILE_A, ["menu"]),
				_cleared_track("missionTheme", FIXTURE_FILE_B, ["miniGame"]),
			]
		)
	)

	if director.is_silent_build():
		failures.append("a cleared, present track must make this a non-silent build")

	# -- Fade in ------------------------------------------------------------
	if not director.set_state(director.STATE_MENU):
		failures.append("a cleared, present track must play")
	if director.current_track_id() != "menuTheme":
		failures.append("the menu state must resolve to the track that declares it")
	if not started.has("menuTheme"):
		failures.append("track_started was not emitted")
	var voice_a: int = _voice_of(director, "menuTheme")
	if voice_a < 0:
		failures.append("no voice holds the playing track")
		director.free()
		return failures
	if director.voice_level(voice_a) > 0.01:
		failures.append(
			"the track started at %.3f rather than fading in from silence"
			% director.voice_level(voice_a)
		)
	if not director.is_fading():
		failures.append("a track that has just started must be fading in")

	director.advance(0.2)
	var partial: float = director.voice_level(voice_a)
	if partial <= 0.0 or partial >= 1.0:
		failures.append("after 0.2 s the fade-in should be partway, got %.3f" % partial)
	director.finish_fades()
	if not is_equal_approx(director.voice_level(voice_a), 1.0):
		failures.append("a finished fade-in must reach full level, got %.3f"
				% director.voice_level(voice_a))
	if director.is_fading():
		failures.append("the fade should be over")

	# -- Crossfade ----------------------------------------------------------
	director.set_state(director.STATE_MINI_GAME)
	if director.current_track_id() != "missionTheme":
		failures.append("the mini-game state must switch tracks")
	var voice_b: int = _voice_of(director, "missionTheme")
	if voice_b < 0:
		failures.append("the incoming track has no voice")
	elif voice_b == voice_a:
		failures.append(
			"the incoming track reused the outgoing voice; a crossfade needs both to sound at once"
		)
	director.advance(0.3)
	if voice_b >= 0:
		var outgoing: float = director.voice_level(voice_a)
		var incoming: float = director.voice_level(voice_b)
		if outgoing <= 0.0 or outgoing >= 1.0:
			failures.append("mid-crossfade the old track should be part way down, got %.3f"
					% outgoing)
		if incoming <= 0.0 or incoming >= 1.0:
			failures.append("mid-crossfade the new track should be part way up, got %.3f"
					% incoming)
		if outgoing <= 0.0 and incoming <= 0.0:
			failures.append("both voices are silent mid-crossfade; that is a gap, not a crossfade")
	director.finish_fades()
	if director.voice_track_id(voice_a) != "":
		failures.append("a finished fade-out must release its voice rather than hold a stream")
	if director.current_track_id() != "missionTheme":
		failures.append("after the crossfade the new track must be the current one")

	# Re-requesting the same state must not restart the track.
	var started_count: int = started.size()
	director.set_state(director.STATE_MINI_GAME)
	if started.size() != started_count:
		failures.append("re-entering the same state restarted the music")

	# A state with no track fades out and says so, without erroring.
	director.set_state(director.STATE_REWARD)
	if director.is_playing_music():
		failures.append("a state with no declared track must not keep the old one playing")
	if stopped.is_empty():
		failures.append("music_stopped was not emitted when the music went away")
	director.finish_fades()
	for index in range(2):
		if director.voice_track_id(index) != "":
			failures.append("every voice must be released once the music has stopped")

	# And back again: returning to a state with a track plays it afresh.
	director.set_state(director.STATE_MENU)
	director.finish_fades()
	if director.current_track_id() != "menuTheme":
		failures.append("returning to a state with a track must play it again")

	# The loop points from the manifest reach the stream, so a delivered track
	# actually loops instead of playing once and leaving the room silent.
	var voice_menu: int = _voice_of(director, "menuTheme")
	if voice_menu >= 0:
		var player: AudioStreamPlayer = director.voice_player(voice_menu)
		var stream: AudioStream = player.stream if player != null else null
		if stream == null:
			failures.append("the playing voice has no stream")
		elif stream is AudioStreamWAV:
			if (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
				failures.append(
					"music must loop; a track that plays once leaves the room silent for the "
					+ "rest of the session"
				)

	director.free()
	return failures


# -----------------------------------------------------------------------------
# 5. Mixer
# -----------------------------------------------------------------------------


func _test_volume_controls():
	var failures: Array = []

	var director: Node = _director_script.new()
	director.set_manifest(_manifest([_cleared_track("menuTheme", FIXTURE_FILE_A, ["menu"])]))

	# Trims attenuate only, and clamp at both ends.
	for setter: Array in [
		["set_master_volume_db", "get_master_volume_db"],
		["set_music_volume_db", "get_music_volume_db"],
		["set_sfx_volume_db", "get_sfx_volume_db"],
	]:
		director.call(String(setter[0]), 24.0)
		var raised: float = float(director.call(String(setter[1])))
		if raised > director.MAX_TRIM_DB:
			failures.append(
				("%s accepted %.1f dB. A trim may only attenuate: nothing in this game plays "
				+ "louder than the level its asset was authored at.") % [setter[0], raised]
			)
		director.call(String(setter[0]), -500.0)
		if float(director.call(String(setter[1]))) < director.MIN_TRIM_DB:
			failures.append("%s did not clamp at MIN_TRIM_DB" % setter[0])
		director.call(String(setter[0]), 0.0)

	# The music ceiling holds however the trims are set, because music plays under
	# the English the child is meant to hear.
	director.set_master_volume_db(0.0)
	director.set_music_volume_db(0.0)
	var loud: Node = _director_script.new()
	loud.set_manifest(
		_manifest([_cleared_track("menuTheme", FIXTURE_FILE_A, ["menu"], 0.0)])
	)
	loud.set_state(loud.STATE_MENU)
	if loud.effective_music_volume_db() > _manifest_script.MAX_VOLUME_DB:
		failures.append(
			"with every trim at 0 dB and a manifest asking for 0 dB, music reached %.1f dB -- "
			% loud.effective_music_volume_db()
			+ "above the %.1f dB ceiling" % _manifest_script.MAX_VOLUME_DB
		)
	loud.free()

	# Trims are additive and audible in the result.
	director.set_state(director.STATE_MENU)
	var base: float = director.effective_music_volume_db()
	director.set_master_volume_db(-6.0)
	var trimmed: float = director.effective_music_volume_db()
	if not is_equal_approx(trimmed, base - 6.0) and trimmed > _manifest_script.MIN_VOLUME_DB:
		failures.append(
			"a -6 dB master trim moved music from %.1f to %.1f dB; trims must be additive"
			% [base, trimmed]
		)
	director.set_music_volume_db(-6.0)
	if director.effective_music_volume_db() >= trimmed:
		failures.append("the music trim had no effect on top of the master trim")
	if not is_equal_approx(director.effective_sfx_volume_db(), -6.0):
		failures.append(
			"effects should follow the master trim only, expected -6.0 dB, got %.1f dB"
			% director.effective_sfx_volume_db()
		)
	director.set_sfx_volume_db(-4.0)
	if not is_equal_approx(director.effective_sfx_volume_db(), -10.0):
		failures.append(
			"master and sfx trims must add, expected -10.0 dB, got %.1f dB"
			% director.effective_sfx_volume_db()
		)

	# A trim change must reach the voice that is already playing, not wait for the
	# next transition.
	director.set_master_volume_db(0.0)
	director.set_music_volume_db(0.0)
	director.finish_fades()
	var voice: int = _voice_of(director, "menuTheme")
	if voice >= 0:
		var player: AudioStreamPlayer = director.voice_player(voice)
		var before: float = player.volume_db
		director.set_master_volume_db(-20.0)
		var after: float = player.volume_db
		if after >= before:
			failures.append(
				"lowering the master trim did not lower the playing voice (%.1f -> %.1f dB)"
				% [before, after]
			)

	var mix_events: Array = []
	director.mix_changed.connect(
		func(master: float, music: float, sfx: float, muted: bool) -> void:
			mix_events.append([master, music, sfx, muted])
	)
	director.set_music_volume_db(-2.0)
	if mix_events.is_empty():
		failures.append("mix_changed must fire so a settings screen can reflect the mix")

	director.free()
	return failures


func _test_mute():
	var failures: Array = []

	var director: Node = _director_script.new()
	director.set_manifest(_manifest([_cleared_track("menuTheme", FIXTURE_FILE_A, ["menu"])]))
	director.set_state(director.STATE_MENU)
	director.finish_fades()
	if not director.is_playing_music():
		failures.append("the control case did not play; the mute test would be vacuous")
		director.free()
		return failures

	director.set_muted(true)
	if not director.is_muted():
		failures.append("set_muted(true) must report is_muted() == true")
	if director.is_playing_music():
		failures.append(
			"muting must actually stop the music rather than leave it running inaudibly"
		)
	if director.effective_music_volume_db() != director.OFF_DB:
		failures.append("a muted director must report its music level as off")
	if director.effective_sfx_volume_db() != director.OFF_DB:
		failures.append("mute must cover effects as well as music")
	for index in range(2):
		var player: AudioStreamPlayer = director.voice_player(index)
		if player != null and player.volume_db > director.SILENCE_DB:
			failures.append("a muted voice is still at %.1f dB" % player.volume_db)

	# Muting twice is a no-op, not a second state change.
	director.set_muted(true)
	if not director.is_muted():
		failures.append("muting an already-muted director changed something")

	# Unmuting restores the same mix, and the music comes back.
	director.set_muted(false)
	if director.is_muted():
		failures.append("set_muted(false) did not unmute")
	director.finish_fades()
	if not director.is_playing_music():
		failures.append(
			"unmuting did not bring the music back. The state never changed, so the child should "
			+ "hear the same thing they did before muting."
		)
	if director.current_track_id() != "menuTheme":
		failures.append("unmuting restored the wrong track")

	if not director.toggle_mute():
		failures.append("toggle_mute() should report the new state")
	if director.toggle_mute():
		failures.append("toggling twice should return to unmuted")

	# Muting while silent, and changing state while muted, must both be quiet
	# no-ops rather than errors.
	director.set_state(director.STATE_SILENT)
	director.set_muted(true)
	director.set_state(director.STATE_MENU)
	if director.is_playing_music():
		failures.append("a muted director must not start playing on a state change")
	director.set_muted(false)
	director.finish_fades()
	if not director.is_playing_music():
		failures.append(
			"the state requested while muted must take effect when sound comes back"
		)

	director.free()
	return failures


func _test_sfx_player_binding():
	var failures: Array = []

	var sfx_script: Resource = load(SFX_SCRIPT)
	if sfx_script == null or not (sfx_script is GDScript):
		return ["could not load %s" % SFX_SCRIPT]

	var director: Node = _director_script.new()
	var sfx: Node = (sfx_script as GDScript).new()
	director.add_child(sfx)
	director.bind_sfx_player(sfx)
	if director.sfx_player() != sfx:
		failures.append("bind_sfx_player() did not take")

	director.set_master_volume_db(-8.0)
	director.set_sfx_volume_db(-4.0)
	if not is_equal_approx(sfx.get_master_volume_db(), -12.0):
		failures.append(
			"the bound effects player should be at -12.0 dB (master -8 + sfx -4), got %.1f dB. "
			% sfx.get_master_volume_db()
			+ "One mixer must own every level, or the settings screen lies."
		)

	director.set_muted(true)
	if not sfx.is_muted():
		failures.append("muting the director must mute the bound effects player")
	director.set_muted(false)
	if sfx.is_muted():
		failures.append("unmuting the director must unmute the bound effects player")

	# The pass-through, and the unbound no-op.
	var played: Array = []
	sfx.sfx_played.connect(func(name: String) -> void: played.append(name))
	director.play_sfx("gentle_tap")
	if played.size() != 1:
		failures.append("play_sfx() did not reach the bound player")
	director.bind_sfx_player(null)
	director.play_sfx("gentle_tap")
	if played.size() != 1:
		failures.append("play_sfx() must be a no-op once unbound")
	# Anything with the right methods works; a Node without them must not crash.
	var plain: Node = Node.new()
	director.add_child(plain)
	director.bind_sfx_player(plain)
	director.set_master_volume_db(-2.0)
	director.play_sfx("gentle_tap")

	director.free()
	return failures


# -----------------------------------------------------------------------------
# Fixtures
# -----------------------------------------------------------------------------


func _voice_of(director: Node, track_id: String) -> int:
	for index in range(2):
		if director.voice_track_id(index) == track_id:
			return index
	return -1


func _manifest(tracks: Array) -> RefCounted:
	var manifest: RefCounted = _manifest_script.new()
	manifest.ingest_dictionary(
		{"manifestVersion": 1, "musicDir": "res://audio/music", "tracks": tracks}
	)
	return manifest


## A complete row with the licence gate OPEN. `licenseEvidence` names what these
## fixture files really are: our own generated effects.
func _cleared_track(
	track_id: String, path: String, scenes: Array, volume_db: float = -14.0
) -> Dictionary:
	var row: Dictionary = _track(
		track_id, path, scenes, _manifest_script.COMMERCIAL_USE_VERIFIED, EVIDENCE
	)
	row["volumeDb"] = volume_db
	return row


func _track(
	track_id: String,
	path: String,
	scenes: Array,
	commercial_use: Variant,
	evidence: String
) -> Dictionary:
	return {
		"trackId": track_id,
		"source": "test fixture; no audio file is created by this case",
		"createdAt": "2026-09-19",
		"downloadedAt": "2026-09-19",
		"licenseEvidence": evidence,
		"commercialUse": commercial_use,
		"localPath": path,
		"loopStart": 0.0,
		"loopEnd": 0.0,
		"volumeDb": -14.0,
		"usageScenes": scenes,
	}
