extends RefCounted

## Vocabulary review, delivered as a BIAS ON DISTRACTOR SELECTION.
##
## Implements `docs/VOCABULARY_REVIEW_SPEC.md`. The whole feature is this file
## plus one call site: there is no review screen, no quiz mode, no flashcard, no
## popup and no "words you've learned" list, because a child playing a life-sim
## does not want to be tested. Review happens inside an activity the child
## already wants to do -- a `findIt` row that shows the banana it asked for next
## to an apple, a spoon and a toothbrush is three older words re-encountered,
## with zero new content and zero new UI.
##
## ## The one hard promise
##
## **A missing `vocabularyProgress` behaves EXACTLY like today's selection.**
## Not "similarly", not "uniformly in distribution" -- exactly. With no review
## history, or with `reviewWeight` at 0.0, `build_choice_ids()` runs
## `uniform_choice_ids()`, which is a line-for-line copy of
## `ModeHandler.build_choice_ids()` and consumes the RNG in the same order.
## `test_vocab_review.gd` asserts the two agree id-for-id over 250 seeds against
## the real `ModeHandler`, so the claim is checked rather than asserted.
##
## ## Weighting
##
##     weight(word) = NEUTRAL_WEIGHT
##                  + base * recencyFactor(levelsSinceLastSeen)
##                         * strugglingFactor(successCount / exposureCount)
##
## `NEUTRAL_WEIGHT` is the floor, and it is load-bearing in two directions:
##
##   - `base == 0` collapses every weight to the same number, which is what makes
##     `reviewWeight: 0.0` a true off switch rather than an approximation;
##   - a word inside its cooldown window still has the floor, so it is DAMPENED,
##     never banned. A word that could not appear for two levels would be a
##     visible, systematic hole -- exactly the kind of pattern that lets a parent
##     tell which objects were chosen for review.
##
## `recencyFactor` is ZERO inside the cooldown window (an immediately repeated
## word is nagging, not teaching), peaks over levels 2-5, then decays to a long
## tail floor that never reaches zero -- a word never seen again must not fall
## silently out of the rotation.
##
## `strugglingFactor` is deliberately MILD (<= 1 + STRUGGLE_BONUS). Aggressively
## drilling a word a child gets wrong is exactly how a game starts to feel like a
## test.
##
## ## Invisibility
##
## The output is a plain `Array` of object-id Strings in a shuffled order --
## structurally identical to the uniform path, with no marker, no flag and no
## metadata saying which entry was a review pick. The final shuffle is applied to
## the whole set including the target, so a review word is no more likely to sit
## in any particular slot. Distractors are only ever drawn from the pool the
## caller already supplies (same-category first), so review can never introduce
## an object the story would not have shown.
##
## ## Purity
##
## Dictionaries, Arrays, Strings, floats and a `RandomNumberGenerator`. No node,
## no `Vector3`, no autoload, no file access, no network. Loaded by `preload()`
## /`load()`, never by `class_name`: the headless `--script` runner does not
## build Godot's global class cache.

# -- Profile keys ---------------------------------------------------------------

const PROGRESS_KEY: String = "vocabularyProgress"
const SETTINGS_KEY: String = "settings"
const REVIEW_WEIGHT_KEY: String = "reviewWeight"

const KEY_LAST_SEEN: String = "lastSeenLevel"
const KEY_EXPOSURE: String = "exposureCount"
const KEY_SUCCESS: String = "successCount"

## `reviewWeight` when the profile does not name one. 0.0 disables review.
const DEFAULT_REVIEW_WEIGHT: float = 1.0
## Ceiling on the authored `base`, so a hand-edited settings file cannot turn
## review into "the same four words for ever".
const MAX_REVIEW_WEIGHT: float = 4.0

# -- Scheduling constants -------------------------------------------------------

## The floor every candidate gets, review history or not. See the class docs.
const NEUTRAL_WEIGHT: float = 1.0

## Levels since last seen below this get NO review boost. "Immediate repetition
## is forbidden" (spec section 4).
const COOLDOWN_LEVELS: int = 2
## The peak window: this is where resurfacing actually teaches.
const PEAK_START: int = 2
const PEAK_END: int = 5
## Past the peak the boost decays per level, but never below TAIL_FLOOR -- a word
## met once in Level 12 and never again is exactly the word this feature exists
## for.
const TAIL_DECAY: float = 0.12
const TAIL_FLOOR: float = 0.25
## Mild on purpose. A word at 0% success is at most this much more likely than a
## word at 100%.
const STRUGGLE_BONUS: float = 0.35

## A word with no exposures yet has no success rate to speak of; treat it as
## neither struggling nor mastered.
const UNKNOWN_SUCCESS_RATE: float = 1.0


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

## `settings.reviewWeight`, clamped to [0, MAX_REVIEW_WEIGHT]. Any non-numeric or
## negative value falls back to the default rather than disabling review by
## accident.
static func read_review_weight(profile: Variant) -> float:
	var settings: Dictionary = _dict(_dict(profile).get(SETTINGS_KEY, {}))
	return _clean_weight(settings.get(REVIEW_WEIGHT_KEY, null))


# ---------------------------------------------------------------------------
# Progress block
# ---------------------------------------------------------------------------

## The review history out of a profile, sanitised.
##
## Read from the top-level `vocabularyProgress` block first, then from
## `settings.vocabularyProgress`.
##
## The second location is not decoration: `ProfileStore._sanitize()` rebuilds the
## profile from `default_profile()` and copies only the keys it knows, so a
## top-level `vocabularyProgress` is DROPPED on the next save -- while unknown
## keys inside `settings` are explicitly preserved. Until `ProfileStore` learns
## the key (see the report accompanying this change), `settings` is the location
## that actually survives a round trip, and reading both means the day it learns
## it, nothing here has to change and no child loses their history.
static func read_progress(profile: Variant) -> Dictionary:
	var data: Dictionary = _dict(profile)
	var top: Dictionary = sanitize_progress(data.get(PROGRESS_KEY, null))
	if not top.is_empty():
		return top
	return sanitize_progress(_dict(data.get(SETTINGS_KEY, {})).get(PROGRESS_KEY, null))


## A copy of `profile` carrying `progress`, written to both supported locations.
## Pure: the argument is never mutated.
static func write_progress(profile: Variant, progress: Variant) -> Dictionary:
	var updated: Dictionary = _dict(profile).duplicate(true)
	var clean: Dictionary = sanitize_progress(progress)
	updated[PROGRESS_KEY] = clean.duplicate(true)
	var settings: Dictionary = _dict(updated.get(SETTINGS_KEY, {})).duplicate(true)
	settings[PROGRESS_KEY] = clean.duplicate(true)
	updated[SETTINGS_KEY] = settings
	return updated


## Normalises anything into `{wordId: {lastSeenLevel, exposureCount, successCount}}`.
##
## Defensive in the same way `ProfileStore` is: a corrupt entry is dropped
## individually, never taken as a reason to discard the whole block, and
## `successCount` is clamped to `exposureCount` so a hand-edited file cannot
## produce a success rate above 1.
static func sanitize_progress(raw: Variant) -> Dictionary:
	var clean: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return clean
	for key: Variant in (raw as Dictionary).keys():
		if typeof(key) != TYPE_STRING:
			continue
		var word_id: String = String(key).strip_edges()
		if word_id.is_empty():
			continue
		var entry: Variant = (raw as Dictionary)[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var exposures: int = maxi(0, _int_of((entry as Dictionary).get(KEY_EXPOSURE, 0)))
		var successes: int = clampi(_int_of((entry as Dictionary).get(KEY_SUCCESS, 0)), 0, exposures)
		clean[word_id] = {
			KEY_LAST_SEEN: maxi(0, _int_of((entry as Dictionary).get(KEY_LAST_SEEN, 0))),
			KEY_EXPOSURE: exposures,
			KEY_SUCCESS: successes,
		}
	return clean


static func empty_entry() -> Dictionary:
	return {KEY_LAST_SEEN: 0, KEY_EXPOSURE: 0, KEY_SUCCESS: 0}


## Records that `word_id` was on screen during level ordinal `level_ordinal`,
## and whether the child got it right. Returns a NEW progress dictionary.
##
## `success` is the only thing that ever feeds `strugglingFactor`, and it is
## never shown to the child: there is no score, no percentage and no streak
## anywhere in this file.
static func record_exposure(
	progress: Variant, word_id: String, level_ordinal: int, success: bool = false
) -> Dictionary:
	var clean: Dictionary = sanitize_progress(progress)
	var key: String = word_id.strip_edges()
	if key.is_empty():
		return clean
	var entry: Dictionary = _dict(clean.get(key, empty_entry())).duplicate(true)
	entry[KEY_EXPOSURE] = maxi(0, _int_of(entry.get(KEY_EXPOSURE, 0))) + 1
	if success:
		entry[KEY_SUCCESS] = maxi(0, _int_of(entry.get(KEY_SUCCESS, 0))) + 1
	# A negative or absurd ordinal must not rewrite history backwards; keep the
	# newest honest value we have.
	entry[KEY_LAST_SEEN] = maxi(_int_of(entry.get(KEY_LAST_SEEN, 0)), maxi(0, level_ordinal))
	clean[key] = entry
	return clean


## `record_exposure()` for a whole choice row: every id that was on screen is an
## exposure, and the ones in `succeeded_ids` are also successes.
static func record_row(
	progress: Variant, shown_ids: Variant, level_ordinal: int, succeeded_ids: Variant = []
) -> Dictionary:
	var clean: Dictionary = sanitize_progress(progress)
	var wins: Dictionary = {}
	if typeof(succeeded_ids) == TYPE_ARRAY or typeof(succeeded_ids) == TYPE_PACKED_STRING_ARRAY:
		for entry: Variant in succeeded_ids:
			wins[String(entry).strip_edges()] = true
	if typeof(shown_ids) != TYPE_ARRAY and typeof(shown_ids) != TYPE_PACKED_STRING_ARRAY:
		return clean
	var seen: Dictionary = {}
	for entry: Variant in shown_ids:
		var word_id: String = String(entry).strip_edges()
		if word_id.is_empty() or seen.has(word_id):
			continue
		seen[word_id] = true
		clean = record_exposure(clean, word_id, level_ordinal, wins.has(word_id))
	return clean


# ---------------------------------------------------------------------------
# Weighting (pure maths, so the curve can be asserted directly)
# ---------------------------------------------------------------------------

## 0 inside the cooldown, 1 across the 2-5 peak, decaying to TAIL_FLOOR after.
## Never negative, never zero outside the cooldown.
static func recency_factor(levels_since_last_seen: int) -> float:
	if levels_since_last_seen < COOLDOWN_LEVELS:
		return 0.0
	if levels_since_last_seen <= PEAK_END:
		return 1.0
	var decayed: float = 1.0 - TAIL_DECAY * float(levels_since_last_seen - PEAK_END)
	return maxf(TAIL_FLOOR, decayed)


## 1.0 for a word the child always gets right, 1 + STRUGGLE_BONUS at 0% success.
## Mild by construction: the constant is the whole range.
static func struggling_factor(entry: Variant) -> float:
	var data: Dictionary = _dict(entry)
	var exposures: int = maxi(0, _int_of(data.get(KEY_EXPOSURE, 0)))
	if exposures <= 0:
		return 1.0 + STRUGGLE_BONUS * (1.0 - UNKNOWN_SUCCESS_RATE)
	var successes: int = clampi(_int_of(data.get(KEY_SUCCESS, 0)), 0, exposures)
	var rate: float = float(successes) / float(exposures)
	return 1.0 + STRUGGLE_BONUS * (1.0 - rate)


## The selection weight of one word. `base` is `settings.reviewWeight`.
## Always >= NEUTRAL_WEIGHT, so nothing can ever be weighted out of existence.
static func weight_for(entry: Variant, current_level_ordinal: int, base: float) -> float:
	if base <= 0.0:
		return NEUTRAL_WEIGHT
	var data: Dictionary = _dict(entry)
	if data.is_empty():
		return NEUTRAL_WEIGHT
	var last_seen: int = maxi(0, _int_of(data.get(KEY_LAST_SEEN, 0)))
	if last_seen <= 0 or current_level_ordinal <= 0:
		# Never actually placed in the journey: no honest "levels since" to use.
		return NEUTRAL_WEIGHT
	var gap: int = current_level_ordinal - last_seen
	if gap < 0:
		# A profile from a future build, or a hand-edited one. Treat as "just seen".
		gap = 0
	return NEUTRAL_WEIGHT + base * recency_factor(gap) * struggling_factor(data)


# ---------------------------------------------------------------------------
# Choice-set construction
# ---------------------------------------------------------------------------

## The target plus up to `distractor_count` other objects, shuffled.
##
## `options` (all optional):
##   `progress`     the `vocabularyProgress` block,
##   `levelOrdinal` 1-based position of the level being played,
##   `reviewWeight` the `base` above; <= 0 disables review entirely,
##   `objectWords`  objectId -> wordId, when the two differ. Missing entries fall
##                  back to the object id itself, which is how every object in
##                  `objects.json` is keyed today.
##
## With no usable review data this is `uniform_choice_ids()` -- the same
## algorithm, the same RNG draws, the same answer as before this file existed.
static func build_choice_ids(
	target_id: String,
	pool: Array,
	distractor_count: int,
	rng: RandomNumberGenerator = null,
	options: Dictionary = {}
) -> Array:
	var generator: RandomNumberGenerator = rng
	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.randomize()

	var candidates: Array = candidate_ids(target_id, pool)
	var wanted: int = mini(maxi(0, distractor_count), candidates.size())

	if not is_review_active(options) or wanted <= 0:
		return uniform_choice_ids(target_id, candidates, distractor_count, generator)

	var weights: Array = weights_for_candidates(candidates, options)
	var picked: Array = _weighted_sample(candidates, weights, wanted, generator)
	if picked.size() < wanted:
		# Defensive: a degenerate weight vector must never shrink the row, because
		# a row with fewer objects than usual is itself a visible tell.
		return uniform_choice_ids(target_id, candidates, distractor_count, generator)

	var chosen: Array = [target_id]
	chosen.append_array(picked)
	_shuffle(chosen, generator)
	return chosen


## True when there is both a reason and permission to bias selection.
static func is_review_active(options: Dictionary) -> bool:
	if _review_base(options) <= 0.0:
		return false
	return not sanitize_progress(options.get("progress", null)).is_empty()


## The distractor candidates for `target_id`: every distinct, non-empty object id
## in `pool` except the target, in pool order. Identical to the filtering
## `ModeHandler.build_choice_ids()` does.
static func candidate_ids(target_id: String, pool: Variant) -> Array:
	var candidates: Array = []
	if typeof(pool) != TYPE_ARRAY:
		return candidates
	for entry: Variant in (pool as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var object_id: String = String((entry as Dictionary).get("objectId", ""))
		if object_id.is_empty() or object_id == target_id:
			continue
		if candidates.has(object_id):
			continue
		candidates.append(object_id)
	return candidates


## Per-candidate selection weights, aligned with `candidates` by index.
static func weights_for_candidates(candidates: Array, options: Dictionary) -> Array:
	var progress: Dictionary = sanitize_progress(options.get("progress", null))
	var level_ordinal: int = _int_of(options.get("levelOrdinal", 0))
	var base: float = _review_base(options)
	var object_words: Dictionary = _dict(options.get("objectWords", {}))

	var weights: Array = []
	for entry: Variant in candidates:
		var object_id: String = String(entry)
		var word_id: String = String(object_words.get(object_id, object_id))
		weights.append(weight_for(progress.get(word_id, {}), level_ordinal, base))
	return weights


## The pre-review algorithm, preserved verbatim.
##
## Line for line what `ModeHandler.build_choice_ids()` does once the candidate
## list is built: shuffle the candidates, take the first N, shuffle the row. The
## RNG draw ORDER matters as much as the maths -- it is what makes the "a missing
## vocabularyProgress changes nothing" promise exact rather than statistical.
static func uniform_choice_ids(
	target_id: String, candidates: Array, distractor_count: int, rng: RandomNumberGenerator
) -> Array:
	var pool: Array = candidates.duplicate()
	_shuffle(pool, rng)
	var chosen: Array = [target_id]
	for i: int in range(mini(maxi(0, distractor_count), pool.size())):
		chosen.append(pool[i])
	_shuffle(chosen, rng)
	return chosen


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Weighted sampling WITHOUT replacement: a row never shows the same object twice.
static func _weighted_sample(
	candidates: Array, weights: Array, count: int, rng: RandomNumberGenerator
) -> Array:
	var remaining_ids: Array = candidates.duplicate()
	var remaining_weights: Array = weights.duplicate()
	var picked: Array = []

	for _i: int in range(count):
		if remaining_ids.is_empty():
			break
		var total: float = 0.0
		for weight: Variant in remaining_weights:
			total += maxf(0.0, float(weight))
		if total <= 0.0:
			break
		var roll: float = rng.randf() * total
		var index: int = remaining_ids.size() - 1
		var running: float = 0.0
		for j: int in range(remaining_ids.size()):
			running += maxf(0.0, float(remaining_weights[j]))
			if roll < running:
				index = j
				break
		picked.append(remaining_ids[index])
		remaining_ids.remove_at(index)
		remaining_weights.remove_at(index)

	return picked


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = values[i]
		values[i] = values[j]
		values[j] = swap


static func _review_base(options: Variant) -> float:
	return _clean_weight(_dict(options).get("reviewWeight", null))


## One reader for the tunable, so the settings key and the per-call override can
## never disagree about what a missing or malformed value means.
##
## Missing / non-numeric / NaN -> the default (review stays on, because a typo in
## a settings file must not silently delete a feature). A real number is clamped
## to [0, MAX_REVIEW_WEIGHT], so 0.0 -- and only a deliberate 0.0 or below -- is
## the off switch the spec promises.
static func _clean_weight(raw: Variant) -> float:
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return DEFAULT_REVIEW_WEIGHT
	var value: float = float(raw)
	if not is_finite(value):
		return DEFAULT_REVIEW_WEIGHT
	return clampf(value, 0.0, MAX_REVIEW_WEIGHT)


static func _dict(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


static func _int_of(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(round(float(value)))
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value).to_int()
		TYPE_BOOL:
			return 1 if value else 0
		_:
			return 0
