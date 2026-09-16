extends RefCounted
## Behavioural checks for `SfxPlayer`.
##
## The runner has no autoloads, so this also covers the "SaveService is
## missing" path, which is exactly what happens in tests and in any scene
## loaded standalone in the editor.

const PLAYER_SCRIPT: String = "res://scripts/audio/sfx_player.gd"


func test_name() -> String:
	return "audio_sfx_player"


func run() -> Array:
	var failures: Array = []

	var script: Resource = load(PLAYER_SCRIPT)
	if script == null or not (script is GDScript):
		failures.append("could not load %s" % PLAYER_SCRIPT)
		return failures

	var player: Node = (script as GDScript).new()
	if player == null:
		failures.append("could not instantiate SfxPlayer")
		return failures

	# -- Detached (not in the tree): must still be completely safe. -----------
	player.play("this_sfx_does_not_exist")
	player.play("")
	player.play("../../etc/passwd")
	player.play("pickup")

	if player.has_sfx("this_sfx_does_not_exist"):
		failures.append("has_sfx() should be false for an unknown effect")
	if not player.has_sfx("pickup"):
		failures.append("has_sfx('pickup') should be true -- generated WAV not found")

	if player.is_sound_enabled() != true:
		failures.append("is_sound_enabled() must default to true when SaveService is absent")

	var cached: int = player.warm_cache()
	if cached != player.KNOWN_SFX.size():
		failures.append(
			"warm_cache() resolved %d of %d known effects" % [cached, player.KNOWN_SFX.size()]
		)

	# -- Volume clamping: nothing may ever be louder than the ceiling. -------
	player.set_master_volume_db(60.0)
	if player.get_master_volume_db() > player.MAX_OUTPUT_DB:
		failures.append("set_master_volume_db() must clamp to MAX_OUTPUT_DB")
	player.set_master_volume_db(0.0)

	# -- Mute. ---------------------------------------------------------------
	player.set_muted(true)
	if not player.is_muted():
		failures.append("set_muted(true) should report is_muted() == true")
	player.set_muted(false)

	# -- Dispatch, pooling and mute. -----------------------------------------
	#
	# NOTE: the headless runner does its work inside `SceneTree._initialize()`,
	# before the tree starts iterating, so nothing added under `root` is really
	# "inside the tree" yet and no audio can actually be mixed here. What is
	# covered below is all of the player's own logic: stream resolution, the
	# voice pool, round-robin allocation and the mute gate.
	var played: Array = []
	player.sfx_played.connect(func(n: String) -> void: played.append(n))

	player.play("this_sfx_does_not_exist")
	if not played.is_empty():
		failures.append("an unknown effect must not report as played")

	# More plays than there are voices: must not error, must not drop requests.
	for i in range(12):
		player.play("pickup")
	if played.size() != 12:
		failures.append("expected 12 accepted plays, got %d" % played.size())

	var voices: int = 0
	for child in player.get_children():
		if child is AudioStreamPlayer:
			voices += 1
	if voices != player.voice_count:
		failures.append("expected %d pooled voices, got %d" % [player.voice_count, voices])

	# Overlapping effects must land on different voices, not a single one.
	var used_streams: int = 0
	for child in player.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream != null:
			used_streams += 1
	if used_streams != player.voice_count:
		failures.append(
			"expected all %d voices to be used by overlapping plays, got %d"
			% [player.voice_count, used_streams]
		)

	player.stop_all()

	# Muted must suppress playback entirely.
	played.clear()
	player.set_muted(true)
	player.play("pickup")
	if not played.is_empty():
		failures.append("muted SfxPlayer must not play anything")
	player.set_muted(false)

	played.clear()
	player.play("pickup")
	if played.size() != 1:
		failures.append("unmuting must restore playback")

	player.free()
	return failures
