extends RefCounted

## Android has not been built or run. This case defends the three things that
## would silently break an Android build, and that a Mac/iPad-only test run
## cannot notice.
##
## Written alongside `docs/ANDROID_READINESS.md`, which records that NO APK has
## ever been produced from this repository (no SDK, no JDK, no device on the
## build machine). These are static and pure-geometry checks -- they prove
## nothing about a real device and they do not pretend to. What they prove is
## that the code has not *regressed away* from being Android-portable between
## now and the day someone installs the SDK.
##
## The properties, and what each one is protecting:
##
##   1. **The safe-area guards still name Android.** Three files branch on
##      `OS.get_name() == "iOS" or == "Android"`. Delete the Android half -- an
##      easy thing to do while tidying an "iOS-only" project -- and the game
##      still runs on Android, but every HUD control moves under the display
##      cutout and the gesture-navigation bar. There is no crash and no error
##      log; it just looks broken on a device nobody here owns.
##   2. **The joystick clears the Speak button at Android aspect ratios.**
##      `test_joystick.gd` already checks the iOS range (4:3 to ~2.17:1) with
##      cosmetic insets. Android is both *squarer* (a 6:5 foldable inner screen)
##      and *wider* (21:9), and it reports much fatter insets than an iPad ever
##      does -- a landscape display cutout on the left edge plus a gesture bar.
##      Those are the cases checked here.
##   3. **A backendless speech stack is inert, not broken.** Android has no
##      speech provider in this project at all. `SpeechBackend` is what an
##      Android build must fall back to, so it must answer every question with a
##      safe "no" and must never leave a caller awaiting a signal that will not
##      arrive.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const Joystick := preload("res://scripts/input/virtual_joystick.gd")
const HouseHud := preload("res://scripts/gameplay/house_hud.gd")
const SpeechBackendScript := preload("res://scripts/speech/speech_backend.gd")

## Every file that decides whether the platform reports a usable safe area.
## All three must keep the Android branch or the HUD drifts under the cutout.
const SAFE_AREA_GUARD_SOURCES: Array[String] = [
	"res://scripts/ui/safe_area.gd",
	"res://scripts/camera/safe_area_insets.gd",
	"res://scripts/input/virtual_joystick.gd",
]

## Landscape viewports Android can actually produce, at the project's fixed
## 1024 px stretched height. Named so a failure says which device shape broke.
##
## The 6:5 entry is the one iOS never produces: a folded-open foldable inner
## display is nearly square, which squeezes the gap between the joystick's
## activation zone and the centre-bottom Speak button harder than any phone.
const ANDROID_VIEWPORTS: Array = [
	["foldable inner 6:5", Vector2(1229.0, 1024.0)],
	["tablet 16:10", Vector2(1638.0, 1024.0)],
	["tablet 16:9", Vector2(1820.0, 1024.0)],
	["phone 18:9", Vector2(2048.0, 1024.0)],
	["phone 19.5:9", Vector2(2219.0, 1024.0)],
	["phone 20:9", Vector2(2276.0, 1024.0)],
	["phone 21:9", Vector2(2389.0, 1024.0)],
]

## Insets (left, top, right, bottom) in viewport pixels.
##
## Android's are much fatter than an iPad's: held in landscape, the display
## cutout sits on one short edge and the gesture-navigation pill on the other,
## and `DisplayServer.get_display_safe_area()` reports both. The "cutout left"
## and "cutout right" rows are the same device rotated the other way, which is a
## thing a child does constantly and `android:screenOrientation="sensorLandscape"`
## explicitly permits.
const ANDROID_INSETS: Array = [
	["cosmetic minimum", Vector4(24.0, 16.0, 24.0, 16.0)],
	["cutout left + gesture bar", Vector4(120.0, 16.0, 60.0, 48.0)],
	["cutout right + gesture bar", Vector4(60.0, 16.0, 120.0, 48.0)],
	["punch-hole top, tall gesture bar", Vector4(44.0, 72.0, 44.0, 64.0)],
]


func test_name() -> String:
	return "android_platform_guards"


func run():
	var failures: Array = []
	failures.append_array(_test_release_identity_contract())
	failures.append_array(_test_safe_area_guards_still_name_android())
	failures.append_array(_test_joystick_clears_speak_at_android_shapes())
	failures.append_array(_test_joystick_stays_inside_the_safe_area())
	failures.append_array(_test_backendless_speech_is_inert())
	failures.append_array(_test_back_navigation_contract())
	return failures


func _test_release_identity_contract():
	var failures: Array = []
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	if not presets.contains('package/unique_name="com.joinanny.littledays"'):
		failures.append("Android package id must be com.joinanny.littledays before the first Play upload")
	if not presets.contains('application/bundle_identifier="com.pointit.littlebuddy"'):
		failures.append("the independent Apple bundle id changed during the Android package migration")
	if not presets.contains('gradle_build/target_sdk="36"'):
		failures.append("Android target SDK must remain 36")
	if not presets.contains('version/code=2') or not presets.contains('version/name="0.1.1"'):
		failures.append("Android release metadata must be versionCode 2 / versionName 0.1.1 or newer")
	return failures


func _test_back_navigation_contract():
	var failures: Array = []
	var project := FileAccess.get_file_as_string("res://project.godot")
	if not project.contains("config/quit_on_go_back=false"):
		failures.append("Android Back may quit the app before scene navigation handles it")
	if not project.contains("AndroidBack=\"*res://scripts/navigation/android_back.gd\""):
		failures.append("Android Back notification translator is not registered")
	var router := FileAccess.get_file_as_string("res://scripts/navigation/android_back.gd")
	if not router.contains("NOTIFICATION_WM_GO_BACK_REQUEST") or not router.contains("ui_cancel"):
		failures.append("Android Back is not translated into the shared ui_cancel path")
	for source_path: String in [
		"res://scenes/main/main.gd",
		"res://scripts/menu/dress_up_screen.gd",
		"res://scripts/house/house_world.gd",
		"res://scenes/baby_room/baby_room.gd",
		"res://scripts/tutor/tutor_scene.gd",
	]:
		if not FileAccess.get_file_as_string(source_path).contains("ui_cancel"):
			failures.append("%s has no shared Back handler" % source_path)
	return failures


## 1. All three platform guards must still include Android.
func _test_safe_area_guards_still_name_android():
	var failures: Array = []
	for path: String in SAFE_AREA_GUARD_SOURCES:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			failures.append("%s: could not be read" % path)
			continue
		var source: String = file.get_as_text()
		file.close()

		if not source.contains("\"Android\""):
			failures.append(
				("%s: no \"Android\" in the platform guard. On Android the HUD would "
				+ "fall back to the cosmetic margin and sit under the display cutout "
				+ "and the gesture bar.") % path
			)
		# The guard is only meaningful if iOS and Android are treated alike; a
		# file that mentions Android but no longer branches on the platform at
		# all has lost the check in a different way.
		if not source.contains("OS.get_name()"):
			failures.append(
				"%s: no OS.get_name() call -- the safe-area platform guard is gone" % path
			)
	return failures


## 2. The activation zone must never reach the Speak button, at any Android
## landscape shape and with any plausible inset.
func _test_joystick_clears_speak_at_android_shapes():
	var failures: Array = []
	var checked: int = 0

	for viewport_entry in ANDROID_VIEWPORTS:
		var shape_name: String = String(viewport_entry[0])
		var viewport: Vector2 = viewport_entry[1]
		for inset_entry in ANDROID_INSETS:
			var inset_name: String = String(inset_entry[0])
			var insets: Vector4 = inset_entry[1]
			checked += 1

			var zone: Rect2 = Joystick.activation_rect(viewport, insets)
			var speak_left: float = viewport.x * 0.5 - HouseHud.SPEAK_HALF_WIDTH
			var zone_right: float = zone.position.x + zone.size.x

			if zone_right > speak_left:
				failures.append(
					("joystick zone overlaps Speak at %s / %s: zone right edge %.1f, "
					+ "Speak left edge %.1f") % [shape_name, inset_name, zone_right, speak_left]
				)

			# A zone with no area is not "safe", it is a stick a child cannot
			# reach at all.
			if zone.size.x <= 0.0 or zone.size.y <= 0.0:
				failures.append(
					"joystick zone collapsed to %s at %s / %s"
					% [str(zone.size), shape_name, inset_name]
				)

	if checked == 0:
		failures.append("no Android viewport/inset combinations were checked")
	return failures


## The zone must also stay inside the reported safe area, or the thumb rest sits
## under the gesture-navigation bar where Android steals the touch.
func _test_joystick_stays_inside_the_safe_area():
	var failures: Array = []
	for viewport_entry in ANDROID_VIEWPORTS:
		var shape_name: String = String(viewport_entry[0])
		var viewport: Vector2 = viewport_entry[1]
		for inset_entry in ANDROID_INSETS:
			var inset_name: String = String(inset_entry[0])
			var insets: Vector4 = inset_entry[1]

			var zone: Rect2 = Joystick.activation_rect(viewport, insets)
			if zone.position.x < insets.x - 0.01:
				failures.append(
					"joystick zone starts left of the safe area at %s / %s (%.1f < %.1f)"
					% [shape_name, inset_name, zone.position.x, insets.x]
				)
			if zone.position.y < insets.y - 0.01:
				failures.append(
					"joystick zone starts above the safe area at %s / %s (%.1f < %.1f)"
					% [shape_name, inset_name, zone.position.y, insets.y]
				)
			var zone_bottom: float = zone.position.y + zone.size.y
			var safe_bottom: float = viewport.y - insets.w
			if zone_bottom > safe_bottom + 0.01:
				failures.append(
					("joystick zone reaches under the gesture bar at %s / %s "
					+ "(%.1f > %.1f)") % [shape_name, inset_name, zone_bottom, safe_bottom]
				)

			# The resting thumb hint has to be inside the zone it activates.
			var rest: Vector2 = Joystick.rest_origin(zone)
			if not zone.has_point(rest):
				failures.append(
					"joystick rest origin %s is outside its own zone %s at %s / %s"
					% [str(rest), str(zone), shape_name, inset_name]
				)
	return failures


## 3. Android has no speech provider here. The base backend is what it gets, and
## it must be a safe dead end rather than a hang or a crash.
func _test_backendless_speech_is_inert():
	var failures: Array = []
	var backend = SpeechBackendScript.new()
	if backend == null:
		return ["SpeechBackend.new() returned null -- an Android build has no fallback"]

	if backend.is_available():
		failures.append("the backendless SpeechBackend claims to be available")
	if backend.has_permission():
		failures.append("the backendless SpeechBackend claims to have permission")
	if backend.is_listening():
		failures.append("the backendless SpeechBackend claims to be listening")
	if String(backend.get_backend_name()) != "unavailable":
		failures.append(
			"the backendless SpeechBackend names itself '%s', not 'unavailable'"
			% String(backend.get_backend_name())
		)

	# `request_permission()` must ANSWER. A caller that awaits
	# `permission_result` and never gets it is a frozen Speak button.
	var permission_results: Array = []
	backend.permission_result.connect(
		func(granted: bool) -> void: permission_results.append(granted)
	)
	backend.request_permission()
	if permission_results.size() != 1:
		failures.append(
			"request_permission() emitted %d results; a caller awaiting permission_result would hang"
			% permission_results.size()
		)
	elif bool(permission_results[0]):
		failures.append("the backendless SpeechBackend granted permission it does not have")

	# So must `start_listening()`.
	var failure_reasons: Array = []
	backend.recognition_failed.connect(
		func(reason: String) -> void: failure_reasons.append(reason)
	)
	backend.start_listening("en-US")
	if failure_reasons.size() != 1:
		failures.append(
			"start_listening() emitted %d failures; a caller awaiting a result would hang"
			% failure_reasons.size()
		)

	# And it must never invent a transcript. A fabricated "milk" on Android would
	# let a child pass a speaking task without speaking.
	var transcripts: Array = []
	backend.recognized.connect(func(text: String) -> void: transcripts.append(text))
	backend.start_listening("en-US")
	backend.stop_listening()
	if not transcripts.is_empty():
		failures.append(
			"the backendless SpeechBackend produced a transcript %s out of nothing"
			% str(transcripts)
		)

	return failures
