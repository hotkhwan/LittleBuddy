extends RefCounted

## The session survives being interrupted, resumed and rotated.
##
## Two more invariants a mutation sweep found nothing was checking:
##
##   1. `SaveService._notification()` writes the profile when the app is CLOSED
##      or PAUSED. Mutation: the whole branch disabled. SURVIVED. On iOS an app
##      is suspended, not quit -- a parent taking the iPad away mid-level is the
##      normal way this game ends, so this is the save path that matters most and
##      it was the one with no test.
##   2. `SafeAreaInsets.combine()` takes the per-edge MAXIMUM. Mutation: replaced
##      with a per-edge average. SURVIVED. Averaging a notch on the left with a
##      HUD margin on the right puts half a bottle under the Dynamic Island on
##      one side and wastes screen on the other.
##
## What this case deliberately does NOT claim: `display_insets()` returns
## `Vector4.ZERO` on every platform except iOS and Android (by design -- macOS
## reports the safe area in screen coordinates and would inset every render taken
## on a Mac). So the REAL notch numbers cannot be verified anywhere but on a
## device. What is verified here is the pure maths that turns a device rectangle
## into insets, fed the rectangles a device would report.
##
## `run()` and every `_test_*` helper are untyped on purpose (contract §8).

const ProfileStoreScript := preload("res://scripts/save/profile_store.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")
const SafeAreaInsets := preload("res://scripts/camera/safe_area_insets.gd")
const WorldState := preload("res://scripts/house/world_state.gd")

const TEST_PATH: String = "user://test_robust_session_profile.json"

## A landscape iPhone: 2532 x 1170, notch on one short edge, home indicator along
## the bottom. Both orientations are built from these two numbers.
const WINDOW: Vector2i = Vector2i(2532, 1170)
const NOTCH_PX: int = 132
const HOME_PX: int = 42


func test_name() -> String:
	return "robust_session"


func run():
	var failures: Array = []
	failures.append_array(_test_the_app_saves_when_it_is_taken_away())
	failures.append_array(_test_coming_back_lands_somewhere_real())
	failures.append_array(_test_both_notch_sides_are_tracked_separately())
	failures.append_array(_test_insets_survive_every_window_shape())
	_cleanup()
	return failures


## -- 1. Interruption ---------------------------------------------------------------

## The parent takes the iPad away. iOS PAUSES the app; it does not quit it.
func _test_the_app_saves_when_it_is_taken_away():
	var failures: Array = []

	for label: String in ["paused", "closing"]:
		_cleanup()
		var save: Node = SaveServiceScript.new(ProfileStoreScript.new(TEST_PATH))
		save.call("add_stars", 5)
		save.call("set_level_stars", "goodMorning", 3)
		save.call("mark_level_completed", "goodMorning")

		# Delete the file underneath it, so the only thing that can put it back is
		# the notification itself. Without this the assertion would pass on the
		# write `add_stars()` already did, and prove nothing.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
		if FileAccess.file_exists(TEST_PATH):
			failures.append("%s: could not clear the profile file to isolate the notification"
					% label)
			save.free()
			continue

		var notification_code: int = Node.NOTIFICATION_APPLICATION_PAUSED
		if label == "closing":
			notification_code = Node.NOTIFICATION_WM_CLOSE_REQUEST
		save.call("_notification", notification_code)

		if not FileAccess.file_exists(TEST_PATH):
			failures.append(("%s: the profile was not written when the app was interrupted. On iOS "
					+ "this is how a session normally ends -- a level's worth of stars is lost "
					+ "every time.") % label)
			save.free()
			continue

		var stored: Dictionary = ProfileStoreScript.new(TEST_PATH).load_profile()
		if int(stored.get("stars", 0)) != 5:
			failures.append("%s: the interrupted save holds %s stars, expected 5"
					% [label, str(stored.get("stars", null))])
		if int((stored.get("starsByLevel", {}) as Dictionary).get("goodMorning", 0)) != 3:
			failures.append("%s: the interrupted save lost the level rating" % label)
		if not bool((stored.get("levelCompleted", {}) as Dictionary).get("goodMorning", false)):
			failures.append("%s: the interrupted save lost the level completion" % label)
		save.free()

	# An unrelated notification must not write anything -- a save on every frame
	# notification would hammer the flash on a device.
	_cleanup()
	var quiet: Node = SaveServiceScript.new(ProfileStoreScript.new(TEST_PATH))
	quiet.call("_notification", Node.NOTIFICATION_PROCESS)
	if FileAccess.file_exists(TEST_PATH):
		failures.append("an unrelated notification wrote the profile")
	quiet.free()

	return failures


## -- 2. Coming back ----------------------------------------------------------------

## A safe point: the child was somewhere in the house, with stars and a level
## pointer. A cold start must put them back, and an impossible location must fall
## back rather than strand them.
func _test_coming_back_lands_somewhere_real():
	var failures: Array = []
	_cleanup()

	var save: Node = SaveServiceScript.new(ProfileStoreScript.new(TEST_PATH))
	save.call("add_stars", 11)
	save.call("set_current_level", "breakfast")
	save.call("set_world_location", "kitchen", "fromBedroom")
	save.free()

	var resumed: Node = SaveServiceScript.new(ProfileStoreScript.new(TEST_PATH))
	if int(resumed.call("get_stars")) != 11:
		failures.append("a resumed session lost the star total (%d)" % int(resumed.call("get_stars")))
	if String(resumed.call("get_current_level")) != "breakfast":
		failures.append("a resumed session lost the level pointer")
	if String(resumed.call("get_current_room_id")) != "kitchen":
		failures.append("a resumed session lost the room, got '%s'"
				% String(resumed.call("get_current_room_id")))
	resumed.free()

	# An impossible saved room -- renamed, removed, or hand-edited into a compound
	# id -- must resolve to somewhere that exists, never to nowhere.
	for bad_room: Variant in ["attic", "bedroom.bed", "", 7, [], {}, "a/b"]:
		var raw: Dictionary = {
			"profileVersion": 4, "currentRoomId": bad_room, "currentSpawnId": "nowhere",
		}
		var path: String = TEST_PATH
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(raw))
		file.close()

		var profile: Dictionary = ProfileStoreScript.new(path).load_profile()
		var state: RefCounted = WorldState.read_from_profile(profile)
		var room: String = String(state.call("get_room_id"))
		var spawn: String = String(state.call("get_spawn_id"))
		if room.is_empty() or spawn.is_empty():
			failures.append("a saved room of %s resolved to nothing at all" % str(bad_room))
		var resolved: Dictionary = WorldState.resolve(room, spawn)
		if bool(resolved.get("roomFallback", false)):
			failures.append("a saved room of %s resolved to '%s', which the house does not have"
					% [str(bad_room), room])

	_cleanup()
	return failures


## -- 3. Orientation and the notch -------------------------------------------------------

## A landscape iPhone has its notch on the LEFT or on the RIGHT depending on which
## way the child turned it. The two must never be averaged into a symmetric
## margin: that is a bottle under the Dynamic Island on one side and wasted screen
## on the other.
func _test_both_notch_sides_are_tracked_separately():
	var failures: Array = []

	var notch_left: Vector4 = SafeAreaInsets.insets_from_pixels(
		Rect2i(Vector2i(NOTCH_PX, 0), Vector2i(WINDOW.x - NOTCH_PX, WINDOW.y - HOME_PX)), WINDOW)
	var notch_right: Vector4 = SafeAreaInsets.insets_from_pixels(
		Rect2i(Vector2i(0, 0), Vector2i(WINDOW.x - NOTCH_PX, WINDOW.y - HOME_PX)), WINDOW)

	if notch_left.x <= 0.0 or notch_left.z > 0.0001:
		failures.append("a notch on the left produced insets %s; the left edge should be inset and "
				% str(notch_left) + "the right edge should not")
	if notch_right.z <= 0.0 or notch_right.x > 0.0001:
		failures.append("a notch on the right produced insets %s" % str(notch_right))
	if is_equal_approx(notch_left.x, notch_left.z):
		failures.append("the left and right insets came out equal; the two orientations have been "
				+ "averaged into one symmetric margin")
	if notch_left.w <= 0.0 or notch_right.w <= 0.0:
		failures.append("the home indicator is not inset from the bottom in either orientation")

	# `combine()` takes the per-edge MAXIMUM. Averaging would let the smaller of
	# the two win on the edge where the larger one matters.
	var chrome: Vector4 = SafeAreaInsets.chrome_insets()
	var combined: Vector4 = SafeAreaInsets.combine(notch_left, chrome)
	if not is_equal_approx(combined.x, maxf(notch_left.x, chrome.x)):
		failures.append("combine() did not take the worse of the two on the left edge: %s from %s "
				% [str(combined.x), str(notch_left.x)] + "and %s" % str(chrome.x))
	if not is_equal_approx(combined.y, maxf(notch_left.y, chrome.y)):
		failures.append("combine() did not take the worse of the two on the top edge")
	if not is_equal_approx(combined.z, maxf(notch_left.z, chrome.z)):
		failures.append("combine() did not take the worse of the two on the right edge")
	if not is_equal_approx(combined.w, maxf(notch_left.w, chrome.w)):
		failures.append("combine() did not take the worse of the two on the bottom edge")
	if combined.x < notch_left.x or combined.w < notch_left.w:
		failures.append("combining with the HUD margin made a hardware inset SMALLER; content "
				+ "would render under the notch")

	# On a platform that reports no safe area (every desktop run, and every render
	# taken on this machine) the answer is exactly the HUD chrome -- not zero, and
	# not something a Mac's menu bar invented.
	if not SafeAreaInsets.platform_reports_safe_area():
		var here: Vector4 = SafeAreaInsets.current_insets()
		if not (is_equal_approx(here.x, chrome.x) and is_equal_approx(here.y, chrome.y)
				and is_equal_approx(here.z, chrome.z) and is_equal_approx(here.w, chrome.w)):
			failures.append("on a platform with no reported safe area the insets should be exactly "
					+ "the game chrome, got %s" % str(here))

	return failures


## -- 4. Every window shape ----------------------------------------------------------------

## Small (4:3 iPad), wide (19.5:9 iPhone) and the degenerate cases a rotation
## produces on the frame the window is being resized.
func _test_insets_survive_every_window_shape():
	var failures: Array = []
	var maximum: float = float(SafeAreaInsets.MAX_INSET)

	var windows: Array = [
		Vector2i(2048, 1536),   # iPad 4:3
		Vector2i(2532, 1170),   # iPhone 19.5:9
		Vector2i(1170, 2532),   # the same phone, rotated to portrait
		Vector2i(2732, 2048),   # iPad Pro
	]
	for window: Vector2i in windows:
		var inset_px: int = 132
		var safe: Rect2i = Rect2i(
			Vector2i(inset_px, inset_px),
			Vector2i(window.x - inset_px * 2, window.y - inset_px * 2))
		var insets: Vector4 = SafeAreaInsets.insets_from_pixels(safe, window)
		for edge: float in [insets.x, insets.y, insets.z, insets.w]:
			if edge < 0.0:
				failures.append("%s produced a negative inset %s" % [str(window), str(edge)])
			if edge > maximum + 0.0001:
				failures.append("%s produced an inset of %s, past the %s ceiling; the usable "
						% [str(window), str(edge), str(maximum)] + "window would collapse")

	# Degenerate: a zero-size window, a zero-size safe area, and a safe area
	# BIGGER than the window (which a rotation really does report for a frame).
	for bad: Array in [
		[Rect2i(Vector2i.ZERO, Vector2i(100, 100)), Vector2i.ZERO],
		[Rect2i(Vector2i.ZERO, Vector2i.ZERO), WINDOW],
		[Rect2i(Vector2i(-50, -50), Vector2i(WINDOW.x + 200, WINDOW.y + 200)), WINDOW],
	]:
		var insets: Vector4 = SafeAreaInsets.insets_from_pixels(bad[0], bad[1])
		for edge: float in [insets.x, insets.y, insets.z, insets.w]:
			if edge < 0.0 or edge > maximum + 0.0001 or not is_finite(edge):
				failures.append("a degenerate window %s produced insets %s; a rotation frame must "
						% [str(bad), str(insets)] + "never push the camera into the next room")

	# The ceiling itself must leave a usable window on both axes.
	if maximum * 2.0 >= 1.0:
		failures.append("MAX_INSET is %s; two opposite edges could eat the entire screen"
				% str(maximum))

	return failures


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
