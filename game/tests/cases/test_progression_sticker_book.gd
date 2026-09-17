extends RefCounted

## Sticker unlocking and its persistence.
##
## Everything here runs against the real bundled content library plus a fake
## save object, so no autoload is required. The fake mimics the one thing the
## real `SaveService` guarantees: settings survive a JSON round trip.

const StickerBookScript := preload("res://scripts/progression/sticker_book.gd")
const StickerArtScript := preload("res://scripts/progression/sticker_art.gd")
const ContentLibraryScript := preload("res://scripts/content/content_library.gd")


## Stand-in for the `SaveService` autoload. `round_trip()` pushes the settings
## through JSON exactly as `ProfileStore` does when it writes profile.json, so a
## value that cannot survive a real save shows up here as a failure.
class FakeSave extends RefCounted:
	var settings: Dictionary = {}

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		if settings.has(key):
			return settings[key]
		return default_value

	func set_setting(key: String, value: Variant) -> void:
		settings[key] = value

	func round_trip() -> void:
		var text: String = JSON.stringify(settings)
		var parsed: Variant = JSON.parse_string(text)
		settings = parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func test_name() -> String:
	return "progression_sticker_book"


func run():
	var failures: Array = []

	var library: Object = ContentLibraryScript.new()
	if library == null:
		return ["content_library.gd could not be instantiated"]
	library.load_all()

	var stickers: Array = library.get_stickers()
	if stickers.size() < 12:
		failures.append("expected at least 12 stickers, found %d" % stickers.size())
		return failures

	failures.append_array(_test_thresholds(stickers))
	failures.append_array(_test_nothing_unlocked_at_zero(library))
	failures.append_array(_test_below_threshold(library, stickers))
	failures.append_array(_test_idempotent(library))
	failures.append_array(_test_persistence_round_trip(library))
	failures.append_array(_test_star_drop_keeps_stickers(library, stickers))
	failures.append_array(_test_corrupt_data(library))
	failures.append_array(_test_celebrate_once(library, stickers))
	failures.append_array(_test_no_save_service(library))
	failures.append_array(_test_every_sticker_draws(stickers))

	return failures


# ---------------------------------------------------------------------------
# Art: every sticker must actually be drawable
# ---------------------------------------------------------------------------

## A self-intersecting polygon makes Godot's triangulator give up and draw
## nothing -- a blank card that only shows up on the device. Check every sticker
## at a few sizes instead.
func _test_every_sticker_draws(stickers: Array):
	var failures: Array = []
	var sizes: Array[float] = [64.0, 148.0, 320.0]

	for entry: Variant in stickers:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sticker: Dictionary = entry
		var sticker_id: String = String(sticker.get("stickerId", ""))
		var word: String = String(sticker.get("word", "")).to_lower()
		var primitive: String = String(sticker.get("primitive", "sphere")).to_lower()
		var base: Color = StickerArtScript.color_from_hex(
				String(sticker.get("color", "")), StickerArtScript.PEACH)

		for side: float in sizes:
			var rect: Rect2 = Rect2(Vector2.ZERO, Vector2(side, side))
			var parts: Array = StickerArtScript.build_parts(word, primitive, rect, base)

			if parts.is_empty():
				failures.append("sticker '%s' produced no drawable parts at %dpx"
						% [sticker_id, int(side)])
				continue

			for part: Variant in parts:
				if typeof(part) != TYPE_DICTIONARY:
					failures.append("sticker '%s' produced a non-dictionary part" % sticker_id)
					continue
				var part_dict: Dictionary = part
				if String(part_dict.get("kind", "")) != "poly":
					continue
				var points: PackedVector2Array = part_dict.get("points", PackedVector2Array())
				if points.size() < 3:
					failures.append("sticker '%s' has a polygon with %d points at %dpx"
							% [sticker_id, points.size(), int(side)])
					continue
				if Geometry2D.triangulate_polygon(points).is_empty():
					failures.append("sticker '%s' has a polygon that fails to triangulate at %dpx (self-intersecting?)"
							% [sticker_id, int(side)])

	# An unknown word still draws something from its primitive, so a new sticker
	# added to the content pack is never an invisible card.
	for primitive: String in ["sphere", "capsule", "box", "cylinder", "torus", "wat"]:
		var fallback: Array = StickerArtScript.build_parts(
				"somethingNew", primitive, Rect2(Vector2.ZERO, Vector2(148.0, 148.0)),
				StickerArtScript.MINT)
		if fallback.is_empty():
			failures.append("an unknown word with primitive '%s' drew nothing" % primitive)

	return failures


# ---------------------------------------------------------------------------
# Thresholds: reachable and monotonic
# ---------------------------------------------------------------------------

func _test_thresholds(stickers: Array):
	var failures: Array = []
	var previous: int = -1

	for entry: Variant in stickers:
		if typeof(entry) != TYPE_DICTIONARY:
			failures.append("sticker list contains a non-dictionary entry")
			continue
		var sticker: Dictionary = entry
		var sticker_id: String = String(sticker.get("stickerId", ""))
		var raw: Variant = sticker.get("unlockAtStars", null)

		if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
			failures.append("sticker '%s' has a non-numeric unlockAtStars" % sticker_id)
			continue
		var threshold: int = int(raw)

		# Reachable: a threshold of 0 would unlock before the child plays, and a
		# negative one is nonsense. Every sticker must be earnable by playing.
		if threshold < 1:
			failures.append("sticker '%s' unlocks at %d stars; must be >= 1 to be earned"
					% [sticker_id, threshold])
		if threshold > 200:
			failures.append("sticker '%s' unlocks at %d stars; unreachable in practice"
					% [sticker_id, threshold])

		# Monotonic in library order (the library sorts by threshold), and no two
		# stickers share a threshold, so every milestone is its own moment.
		if threshold <= previous:
			failures.append("sticker '%s' threshold %d is not above the previous %d"
					% [sticker_id, threshold, previous])
		previous = threshold

	return failures


# ---------------------------------------------------------------------------
# Unlocking
# ---------------------------------------------------------------------------

func _test_nothing_unlocked_at_zero(library: Object):
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var book: Object = _book(save)

	if book.get_unlocked_count() != 0:
		failures.append("a fresh book reports %d unlocked stickers, expected 0"
				% book.get_unlocked_count())

	var newly: Array = book.sync_with_stars(0, library)
	if not newly.is_empty():
		failures.append("sync_with_stars(0) unlocked %s; expected nothing" % str(newly))

	return failures


func _test_below_threshold(library: Object, stickers: Array):
	var failures: Array = []

	for entry: Variant in stickers:
		var sticker: Dictionary = entry
		var sticker_id: String = String(sticker.get("stickerId", ""))
		var threshold: int = int(sticker.get("unlockAtStars", 0))

		var save: FakeSave = FakeSave.new()
		var book: Object = _book(save)
		book.sync_with_stars(threshold - 1, library)
		if book.is_unlocked(sticker_id):
			failures.append("sticker '%s' unlocked at %d stars but needs %d"
					% [sticker_id, threshold - 1, threshold])

		var at_save: FakeSave = FakeSave.new()
		var at_book: Object = _book(at_save)
		at_book.sync_with_stars(threshold, library)
		if not at_book.is_unlocked(sticker_id):
			failures.append("sticker '%s' did NOT unlock at its own threshold of %d"
					% [sticker_id, threshold])

	return failures


func _test_idempotent(library: Object):
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var book: Object = _book(save)

	var first: Array = book.sync_with_stars(20, library)
	if first.is_empty():
		failures.append("sync_with_stars(20) unlocked nothing; expected several stickers")

	for i: int in range(5):
		var again: Array = book.sync_with_stars(20, library)
		if not again.is_empty():
			failures.append("repeat sync_with_stars(20) #%d unlocked %s; must be idempotent"
					% [i + 1, str(again)])

	var expected: int = library.get_unlocked_stickers(20).size()
	if book.get_unlocked_count() != expected:
		failures.append("after repeated syncs the book holds %d stickers, expected %d"
				% [book.get_unlocked_count(), expected])

	# A second, independent book over the same storage must agree -- otherwise a
	# scene reload would re-unlock and re-celebrate everything.
	var reloaded: Object = _book(save)
	var reload_new: Array = reloaded.sync_with_stars(20, library)
	if not reload_new.is_empty():
		failures.append("a freshly constructed book re-unlocked %s from the same save"
				% str(reload_new))

	return failures


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func _test_persistence_round_trip(library: Object):
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var book: Object = _book(save)

	book.sync_with_stars(15, library)
	var before: Array = book.get_unlocked_ids()
	if before.is_empty():
		failures.append("nothing unlocked at 15 stars; cannot test persistence")
		return failures

	if not save.settings.has(StickerBookScript.SETTING_KEY):
		failures.append("unlocked stickers were not written to settings['%s']"
				% StickerBookScript.SETTING_KEY)
		return failures

	var stored: Variant = save.settings[StickerBookScript.SETTING_KEY]
	if typeof(stored) != TYPE_ARRAY:
		failures.append("settings['%s'] is %s, not an Array; ProfileStore would drop it"
				% [StickerBookScript.SETTING_KEY, type_string(typeof(stored))])

	# Simulate quitting and relaunching the app.
	save.round_trip()
	var reloaded: Object = _book(save)
	var after: Array = reloaded.get_unlocked_ids()

	if after.size() != before.size():
		failures.append("after a save/reload round trip the book holds %d stickers, expected %d"
				% [after.size(), before.size()])
	for sticker_id: Variant in before:
		if not after.has(sticker_id):
			failures.append("sticker '%s' was lost across the save/reload round trip"
					% str(sticker_id))

	return failures


func _test_star_drop_keeps_stickers(library: Object, stickers: Array):
	var failures: Array = []
	var save: FakeSave = FakeSave.new()
	var book: Object = _book(save)

	book.sync_with_stars(30, library)
	var before: Array = book.get_unlocked_ids()
	if before.is_empty():
		failures.append("nothing unlocked at 30 stars; cannot test the star drop")
		return failures

	# Stars somehow drop (a restored profile, a parent reset of the counter).
	# Stickers are a keepsake -- they must never be taken away.
	book.sync_with_stars(0, library)
	var after: Array = book.get_unlocked_ids()

	for sticker_id: Variant in before:
		if not after.has(sticker_id):
			failures.append("sticker '%s' was revoked when the star count dropped"
					% str(sticker_id))

	if stickers.is_empty():
		return failures

	# And the earlier, low-threshold ones are still there too.
	var first_id: String = String((stickers[0] as Dictionary).get("stickerId", ""))
	if not book.is_unlocked(first_id):
		failures.append("the first sticker '%s' was revoked by a star drop" % first_id)

	return failures


# ---------------------------------------------------------------------------
# Corruption
# ---------------------------------------------------------------------------

func _test_corrupt_data(library: Object):
	var failures: Array = []

	var corrupt_values: Array = [
		null,
		"milkSticker",
		42,
		3.5,
		true,
		{"milkSticker": true},
		[],
		[1, 2, 3],
		[null, {}, []],
		["", "   "],
		["milkSticker", 7, null, "milkSticker", {"a": 1}],
	]

	for value: Variant in corrupt_values:
		var save: FakeSave = FakeSave.new()
		save.settings[StickerBookScript.SETTING_KEY] = value
		var book: Object = _book(save)

		var ids: Array = book.get_unlocked_ids()
		if typeof(ids) != TYPE_ARRAY:
			failures.append("corrupt value %s produced a non-Array result" % str(value))
			continue

		for sticker_id: Variant in ids:
			if typeof(sticker_id) != TYPE_STRING:
				failures.append("corrupt value %s survived as a non-String id %s"
						% [str(value), str(sticker_id)])
			elif String(sticker_id).strip_edges().is_empty():
				failures.append("corrupt value %s survived as an empty id" % str(value))

		# Degraded state must still be usable, not just non-crashing.
		var newly: Array = book.sync_with_stars(20, library)
		if typeof(newly) != TYPE_ARRAY:
			failures.append("sync_with_stars after corrupt value %s returned a non-Array"
					% str(value))
		if book.get_unlocked_count() < library.get_unlocked_stickers(20).size():
			failures.append("after recovering from corrupt value %s the book only holds %d stickers"
					% [str(value), book.get_unlocked_count()])

	# The one genuinely salvageable case: a valid id mixed with junk is kept.
	var mixed_save: FakeSave = FakeSave.new()
	mixed_save.settings[StickerBookScript.SETTING_KEY] = ["milkSticker", 7, null, "milkSticker"]
	var mixed_book: Object = _book(mixed_save)
	var mixed_ids: Array = mixed_book.get_unlocked_ids()
	if mixed_ids != ["milkSticker"]:
		failures.append("mixed junk should sanitize to ['milkSticker'], got %s" % str(mixed_ids))

	return failures


# ---------------------------------------------------------------------------
# Celebrate-once
# ---------------------------------------------------------------------------

func _test_celebrate_once(library: Object, stickers: Array):
	var failures: Array = []
	if stickers.is_empty():
		return failures

	var first: Dictionary = stickers[0]
	var threshold: int = int(first.get("unlockAtStars", 1))
	var first_id: String = String(first.get("stickerId", ""))

	var save: FakeSave = FakeSave.new()
	var book: Object = _book(save)

	var celebrated: Array = book.register_star_change(threshold - 1, threshold, library)
	var celebrated_ids: Array = _ids_of(celebrated)
	if not celebrated_ids.has(first_id):
		failures.append("crossing %d stars did not offer '%s' to celebrate"
				% [threshold, first_id])

	# Replaying the exact same star transition (a re-entered scene, a duplicated
	# signal) must not celebrate the sticker a second time.
	var replay: Array = book.register_star_change(threshold - 1, threshold, library)
	if not replay.is_empty():
		failures.append("replaying the same star change re-celebrated %s" % str(_ids_of(replay)))

	if not book.is_unlocked(first_id):
		failures.append("'%s' was celebrated but not persisted" % first_id)

	# A later transition still celebrates only what is genuinely new.
	var big: Array = book.register_star_change(threshold, 30, library)
	for sticker_id: Variant in _ids_of(big):
		if String(sticker_id) == first_id:
			failures.append("'%s' was celebrated again during a later star change" % first_id)

	return failures


# ---------------------------------------------------------------------------
# No save service attached
# ---------------------------------------------------------------------------

func _test_no_save_service(library: Object):
	var failures: Array = []
	var book: Object = StickerBookScript.new()
	book.attach(null)

	if book.has_save_service():
		failures.append("a book attached to null claims to have a save service")

	var newly: Array = book.sync_with_stars(10, library)
	if newly.is_empty():
		failures.append("a memory-only book unlocked nothing at 10 stars")
	if book.sync_with_stars(10, library).size() != 0:
		failures.append("a memory-only book is not idempotent")

	# An object missing the settings API must be refused, not half-wired.
	var bogus: Object = RefCounted.new()
	var refused: Object = StickerBookScript.new()
	refused.attach(bogus)
	if refused.has_save_service():
		failures.append("a book accepted an object without get_setting/set_setting")

	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _book(save: Object) -> Object:
	var book: Object = StickerBookScript.new()
	book.attach(save)
	return book


func _ids_of(stickers: Array) -> Array:
	var ids: Array = []
	for entry: Variant in stickers:
		if typeof(entry) == TYPE_DICTIONARY:
			ids.append(String((entry as Dictionary).get("stickerId", "")))
	return ids
