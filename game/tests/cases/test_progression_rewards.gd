extends RefCounted

## Star awarding: one completion, one payout. Ever.
##
## The regression this exists to stop is a completion paying out twice -- a
## signal connected twice, a retried award, a scene reloaded mid-celebration, or
## a child hammering the same object. All of those must leave the star total
## exactly where a single award would.

const RewardLedgerScript := preload("res://scripts/progression/reward_ledger.gd")
const StickerBookScript := preload("res://scripts/progression/sticker_book.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")


## Stand-in for the `SaveService` autoload, counting every call so a
## double-award shows up as a wrong total AND a wrong call count.
class FakeSave extends RefCounted:
	var stars: int = 0
	var add_calls: int = 0
	var completed: Array = []
	var settings: Dictionary = {}

	func get_stars() -> int:
		return stars

	func add_stars(amount: int) -> int:
		add_calls += 1
		stars = maxi(stars + amount, 0)
		return stars

	func mark_activity_completed(activity_id: String) -> void:
		if not completed.has(activity_id):
			completed.append(activity_id)

	func is_activity_completed(activity_id: String) -> bool:
		return completed.has(activity_id)

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		if settings.has(key):
			return settings[key]
		return default_value

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value


## Hand-driven clock so the spam-tap window is deterministic.
class FakeClock extends RefCounted:
	var now_ms: int = 100_000

	func advance(ms: int) -> void:
		now_ms += ms

	func read() -> int:
		return now_ms


func test_name() -> String:
	return "progression_rewards"


func run():
	var failures: Array = []

	failures.append_array(_test_single_award())
	failures.append_array(_test_no_double_award())
	failures.append_array(_test_spam_taps())
	failures.append_array(_test_invalid_awards())
	failures.append_array(_test_session_totals())
	failures.append_array(_test_claim_guard())
	failures.append_array(_test_stickers_not_double_unlocked())

	return failures


# ---------------------------------------------------------------------------

func _test_single_award() -> Array:
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var ledger: Object = _ledger(FakeClock.new())

	var result: Dictionary = ledger.award("task.feedMilk.1", 1, save)

	if int(result.get("granted", -1)) != 1:
		failures.append("a first award granted %s stars, expected 1" % str(result.get("granted")))
	if int(result.get("previousStars", -1)) != 0:
		failures.append("previousStars was %s, expected 0" % str(result.get("previousStars")))
	if int(result.get("stars", -1)) != 1:
		failures.append("total after the award was %s, expected 1" % str(result.get("stars")))
	if save.stars != 1:
		failures.append("the save holds %d stars after one award, expected 1" % save.stars)
	if not save.completed.has("task.feedMilk.1"):
		failures.append("the completion was not marked in the save")

	return failures


func _test_no_double_award() -> Array:
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var clock: FakeClock = FakeClock.new()
	var ledger: Object = _ledger(clock)

	ledger.award("task.feedMilk.1", 1, save)

	# Replay the same completion several times, with plenty of time between so
	# the spam guard is NOT what is being tested here -- only the id guard.
	for i: int in range(6):
		clock.advance(5_000)
		var repeat: Dictionary = ledger.award("task.feedMilk.1", 1, save)
		if int(repeat.get("granted", -1)) != 0:
			failures.append("replay #%d of the same completion granted %s stars"
					% [i + 1, str(repeat.get("granted"))])
		if not bool(repeat.get("duplicate", false)):
			failures.append("replay #%d was not reported as a duplicate" % [i + 1])

	if save.stars != 1:
		failures.append("after 7 reports of one completion the save holds %d stars, expected 1"
				% save.stars)
	if save.add_calls != 1:
		failures.append("add_stars() was called %d times for one completion, expected 1"
				% save.add_calls)

	# A genuinely different completion still pays out.
	clock.advance(5_000)
	var other: Dictionary = ledger.award("task.feedMilk.2", 1, save)
	if int(other.get("granted", -1)) != 1:
		failures.append("a different completion was refused after a duplicate")
	if save.stars != 2:
		failures.append("the save holds %d stars after two distinct completions, expected 2"
				% save.stars)

	return failures


func _test_spam_taps() -> Array:
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var clock: FakeClock = FakeClock.new()
	var ledger: Object = _ledger(clock)

	ledger.award("tap.1", 1, save)

	# Twenty different completion ids fired within a few milliseconds: that is
	# not a child playing, that is a spam tap or a duplicated signal.
	for i: int in range(20):
		clock.advance(5)
		ledger.award("tap.spam.%d" % i, 1, save)

	if save.stars != 1:
		failures.append("spam taps awarded %d stars, expected 1" % save.stars)

	# Once the child is genuinely playing again, rewards resume immediately --
	# spam is ignored, never punished.
	clock.advance(2_000)
	var resumed: Dictionary = ledger.award("tap.2", 1, save)
	if int(resumed.get("granted", -1)) != 1:
		failures.append("a real completion after spam taps was refused: %s" % str(resumed))

	# A spam-refused id is NOT burned: the same task can still pay out later.
	clock.advance(2_000)
	var retried: Dictionary = ledger.award("tap.spam.0", 1, save)
	if int(retried.get("granted", -1)) != 1:
		failures.append("an id refused as a spam tap could never be earned again")

	return failures


func _test_invalid_awards() -> Array:
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var clock: FakeClock = FakeClock.new()
	var ledger: Object = _ledger(clock)

	var cases: Array = [["", 1], ["   ", 1], ["task.x", 0], ["task.x", -5]]
	for entry: Variant in cases:
		var case_data: Array = entry
		clock.advance(5_000)
		var result: Dictionary = ledger.award(String(case_data[0]), int(case_data[1]), save)
		if int(result.get("granted", -1)) != 0:
			failures.append("award('%s', %d) granted %s stars, expected 0"
					% [str(case_data[0]), int(case_data[1]), str(result.get("granted"))])

	if save.stars != 0:
		failures.append("invalid awards changed the save to %d stars" % save.stars)
	if save.add_calls != 0:
		failures.append("invalid awards still called add_stars() %d times" % save.add_calls)

	# A content value that is far too generous is clamped, not honoured.
	clock.advance(5_000)
	var huge: Dictionary = ledger.award("task.huge", 9_999, save)
	if int(huge.get("granted", 0)) > RewardLedgerScript.MAX_STARS_PER_AWARD:
		failures.append("an award of 9999 stars was not clamped (granted %s)"
				% str(huge.get("granted")))

	return failures


func _test_session_totals() -> Array:
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var clock: FakeClock = FakeClock.new()
	var ledger: Object = _ledger(clock)

	for i: int in range(5):
		clock.advance(1_000)
		ledger.award("session.task.%d" % i, 1, save)

	if ledger.get_session_stars() != 5:
		failures.append("session stars were %d after 5 completions, expected 5"
				% ledger.get_session_stars())
	if ledger.get_session_completions() != 5:
		failures.append("session completions were %d, expected 5"
				% ledger.get_session_completions())

	# A new session zeroes the counter but keeps the duplicate guard, so last
	# session's completions cannot be re-earned by starting a new one.
	ledger.begin_session()
	if ledger.get_session_stars() != 0:
		failures.append("a new session did not reset the session star count")

	clock.advance(5_000)
	var replay: Dictionary = ledger.award("session.task.0", 1, save)
	if int(replay.get("granted", -1)) != 0:
		failures.append("a new session let an old completion pay out again")
	if save.stars != 5:
		failures.append("the save holds %d stars after a new session, expected 5" % save.stars)

	return failures


func _test_claim_guard() -> Array:
	var failures: Array = []
	var ledger: Object = _ledger(FakeClock.new())

	if not ledger.claim("mission.morning"):
		failures.append("the first claim of an id was refused")
	for i: int in range(4):
		if ledger.claim("mission.morning"):
			failures.append("claim #%d of the same id succeeded again" % [i + 2])
	if not ledger.is_claimed("mission.morning"):
		failures.append("is_claimed() did not report a claimed id")
	if ledger.claim(""):
		failures.append("an empty id was claimable")

	# A claimed id can never then be awarded.
	var save: FakeSave = FakeSave.new()
	var result: Dictionary = ledger.award("mission.morning", 3, save)
	if int(result.get("granted", -1)) != 0:
		failures.append("an already-claimed id was still awarded stars")
	if save.stars != 0:
		failures.append("an already-claimed id changed the save to %d stars" % save.stars)

	return failures


# ---------------------------------------------------------------------------
# Ledger + sticker book together: the full award path
# ---------------------------------------------------------------------------

func _test_stickers_not_double_unlocked() -> Array:
	var failures: Array = []

	var library: Object = ContentLibraryScript.new()
	if library == null:
		return ["content_library.gd could not be instantiated"]
	library.load_all()

	var save: FakeSave = FakeSave.new()
	var clock: FakeClock = FakeClock.new()
	var ledger: Object = _ledger(clock)
	var book: Object = StickerBookScript.new()
	book.attach(save)

	var celebrated: Array = []

	# Play twelve tasks, reporting each one twice (the exact double-signal bug
	# this guard exists for).
	for i: int in range(12):
		for _repeat: int in range(2):
			clock.advance(1_000)
			var result: Dictionary = ledger.award("play.task.%d" % i, 1, save)
			if int(result.get("granted", 0)) <= 0:
				continue
			for sticker: Variant in book.register_star_change(
					int(result.get("previousStars", 0)), int(result.get("stars", 0)), library):
				celebrated.append(String((sticker as Dictionary).get("stickerId", "")))

	if save.stars != 12:
		failures.append("12 tasks reported twice each awarded %d stars, expected 12" % save.stars)

	var expected_ids: Array = []
	for sticker: Variant in library.get_unlocked_stickers(12):
		expected_ids.append(String((sticker as Dictionary).get("stickerId", "")))

	if celebrated.size() != expected_ids.size():
		failures.append("celebrated %d stickers (%s), expected %d (%s)"
				% [celebrated.size(), str(celebrated), expected_ids.size(), str(expected_ids)])

	var seen: Dictionary = {}
	for sticker_id: Variant in celebrated:
		if seen.has(sticker_id):
			failures.append("sticker '%s' was celebrated twice" % str(sticker_id))
		seen[sticker_id] = true
		if not expected_ids.has(sticker_id):
			failures.append("sticker '%s' was celebrated but is not earned at 12 stars"
					% str(sticker_id))

	if book.get_unlocked_count() != expected_ids.size():
		failures.append("the book holds %d stickers at 12 stars, expected %d"
				% [book.get_unlocked_count(), expected_ids.size()])

	return failures


# ---------------------------------------------------------------------------

func _ledger(clock: FakeClock) -> Object:
	var ledger: Object = RewardLedgerScript.new()
	ledger.clock = Callable(clock, "read")
	return ledger
