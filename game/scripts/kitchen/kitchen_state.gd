extends RefCounted

## THE KITCHEN, AS STATE: what is in Aliz's hand, what is sitting on each
## station, and which doors are open.
##
## Every verb the brief asks for is a method here, and each one RETURNS what
## happened rather than mutating quietly:
##
##   openFridge / closeFridge   `set_open()`
##   takeIngredient / pickUpItem `take()`
##   carryItem                   `held()` -- carrying is just holding while walking
##   placeOnCounter              `place()`
##   takeUtensil                 `take()` (a spoon is an item; a utensil is a role)
##   combineIngredients          `place()` when the two combine
##   prepareFood                 `place()` returning a `gesture`
##   serveFood                   `place()` on the `serve` station
##   putItemAway                 `place()` back into a `store` station
##
## There is no separate `combine()` or `prepare()` verb, and that is deliberate.
## To a child there is one action -- *put the thing you are holding onto the
## thing in front of you* -- and what it MEANS is the kitchen's job to work out,
## not the child's to select from a menu.
##
## Every method returns a report:
##   {ok, verb, item, result, gesture, station, say}
## `say` is the child-facing line, and it is never empty on a refusal: a tap that
## does nothing and explains nothing is the dead end this project keeps banning.
##
## PURE. The node layer (`kitchen_view.gd`) watches the signals and moves meshes;
## this file has never heard of a mesh.

const Items := preload("res://scripts/kitchen/kitchen_items.gd")
const Rules := preload("res://scripts/kitchen/kitchen_rules.gd")

## Emitted after any change, so the view redraws from one place rather than each
## verb remembering to tell it.
signal changed()
## A station's door moved. The view rotates the actual door on this.
signal openness_changed(station_id: String, is_open: bool)
## Something became something else. The view plays the transformation on this --
## it is the moment the brief calls "the resulting food changes visually".
signal item_transformed(station_id: String, from_a: String, from_b: String, result: String)

var _hand: String = Items.NONE
var _on: Dictionary = {}       # stationId -> itemId resting on it
var _inside: Dictionary = {}   # stationId -> Array of itemIds stored inside
var _open: Dictionary = {}     # stationId -> bool


func _init() -> void:
	reset()


## Back to the start of the day: fridge shut, hands empty, everything where it
## belongs. Called on mission start so a replay is never half-cooked.
func reset() -> void:
	_hand = Items.NONE
	_on.clear()
	_inside.clear()
	_open.clear()
	for station_id: Variant in Rules.STATIONS.keys():
		var id: String = String(station_id)
		_inside[id] = Rules.initial_contents(id)
		_on[id] = Items.NONE
		_open[id] = false
	changed.emit()


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

func held() -> String:
	return _hand


func is_holding(item_id: String) -> bool:
	return _hand == item_id and _hand != Items.NONE


func on_station(station_id: String) -> String:
	return String(_on.get(station_id, Items.NONE))


func inside(station_id: String) -> Array:
	var got: Variant = _inside.get(station_id, [])
	return (got as Array).duplicate() if got is Array else []


func is_open(station_id: String) -> bool:
	return bool(_open.get(station_id, false))


## Everything a station is showing right now, for the view and for the test.
func describe(station_id: String) -> Dictionary:
	return {
		"stationId": station_id,
		"role": Rules.role_of(station_id),
		"open": is_open(station_id),
		"on": on_station(station_id),
		"inside": inside(station_id),
	}


# ---------------------------------------------------------------------------
# The verbs
# ---------------------------------------------------------------------------

## openFridge / closeFridge. Returns a report; refuses stations with no door
## rather than silently pretending, so a content error surfaces.
func set_open(station_id: String, open: bool) -> Dictionary:
	if not Rules.opens(station_id):
		return _no("open", station_id, "", "That one doesn't open!")
	if is_open(station_id) == open:
		return _no("open", station_id, "", "")
	_open[station_id] = open
	openness_changed.emit(station_id, open)
	changed.emit()
	var word: String = String(Rules.station(station_id).get("word", "door"))
	return _yes("open" if open else "close", station_id, "", "",
			("Open the %s!" if open else "Close the %s!") % word)


## takeIngredient / pickUpItem / takeUtensil -- one verb, because they are one
## act. Takes from INSIDE a store station, or from the top of a prepare station.
func take(station_id: String, item_id: String) -> Dictionary:
	if _hand != Items.NONE:
		return _no("take", station_id, item_id,
				Rules.refusal_for(station_id, item_id, _hand, is_open(station_id)))

	# From the surface first: a thing you can see is the thing you meant.
	if on_station(station_id) == item_id and item_id != Items.NONE:
		_on[station_id] = Items.NONE
		_hand = item_id
		changed.emit()
		return _yes("take", station_id, item_id, "",
				"You have the %s!" % Items.word_for(item_id))

	var contents: Array = inside(station_id)
	if not Rules.can_take(station_id, item_id, contents, _hand, is_open(station_id)):
		return _no("take", station_id, item_id,
				Rules.refusal_for(station_id, item_id, _hand, is_open(station_id)))
	contents.erase(item_id)
	_inside[station_id] = contents
	_hand = item_id
	changed.emit()
	return _yes("take", station_id, item_id, "",
			"You have the %s!" % Items.word_for(item_id))


## placeOnCounter / combineIngredients / prepareFood / serveFood / putItemAway.
##
## Putting a thing down is one action whose MEANING depends on what is already
## there -- which is the whole design. The report says which it turned out to be,
## so the caller can open a close-up for a `prepare` without deciding that here.
func place(station_id: String) -> Dictionary:
	if _hand == Items.NONE:
		return _no("place", station_id, "", "Let's find something to carry first!")
	var item: String = _hand
	var resting: String = on_station(station_id)

	# Does it combine with what is already there?
	var result: String = Rules.combination(station_id, resting, item)
	if result != Items.NONE:
		_on[station_id] = result
		_hand = Items.NONE
		item_transformed.emit(station_id, resting, item, result)
		changed.emit()
		return _yes("prepare", station_id, item, result,
				"You made %s!" % Items.word_for(result), Rules.gesture_for(result))

	if not Rules.can_place(station_id, item, resting):
		return _no("place", station_id, item,
				Rules.refusal_for(station_id, item, Items.NONE, is_open(station_id)))

	# Putting something back where it lives, rather than onto the top.
	if Rules.role_of(station_id) == "store" and is_open(station_id):
		var contents: Array = inside(station_id)
		contents.append(item)
		_inside[station_id] = contents
		_hand = Items.NONE
		changed.emit()
		return _yes("putAway", station_id, item, "",
				"The %s is away!" % Items.word_for(item))

	_on[station_id] = item
	_hand = Items.NONE
	changed.emit()
	var verb: String = "serve" if Rules.role_of(station_id) == "serve" else "place"
	return _yes(verb, station_id, item, "",
			"The %s is on the %s." % [Items.word_for(item),
					String(Rules.station(station_id).get("word", "table"))])


## Hands the held item to Bunny. Separate from `place()` because Bunny is not a
## station -- and because feeding is the one act with a consequence outside the
## kitchen.
func give_to_bunny() -> Dictionary:
	if _hand == Items.NONE:
		return _no("feed", "", "", "Let's get Bunny some food first!")
	if not Rules.is_feedable(_hand):
		return _no("feed", "", _hand,
				"Bunny doesn't eat the %s!" % Items.word_for(_hand))
	var fed: String = _hand
	_hand = Items.NONE
	changed.emit()
	return _yes("feed", "", fed, "", "Yum! Thank you!")


## Free Play's pantry refills. Every raw ingredient a station started the day
## with that is no longer anywhere in the kitchen -- not in the hand, not on a
## station, not inside one -- goes back where it lives. Called after Bunny has
## been fed, so the milk, the banana and the bowl they were made from are there
## to be made again: Free Play has no objective and nothing in it is ever used
## up. Returns `[{"station": id, "item": id}]` for what came back.
func restock() -> Array:
	var present: Array = [_hand]
	for station_id: Variant in Rules.STATIONS.keys():
		var id: String = String(station_id)
		present.append(on_station(id))
		present.append_array(inside(id))
	var returned: Array = []
	for station_id: Variant in Rules.STATIONS.keys():
		var id: String = String(station_id)
		var contents: Array = inside(id)
		for item: Variant in Rules.initial_contents(id):
			var item_id: String = String(item)
			if present.has(item_id):
				continue
			contents.append(item_id)
			present.append(item_id)
			returned.append({"station": id, "item": item_id})
		_inside[id] = contents
	if not returned.is_empty():
		changed.emit()
	return returned


# ---------------------------------------------------------------------------

func _yes(verb: String, station_id: String, item: String, result: String,
		say: String, gesture: String = "") -> Dictionary:
	return {"ok": true, "verb": verb, "station": station_id, "item": item,
			"result": result, "say": say, "gesture": gesture}


func _no(verb: String, station_id: String, item: String, say: String) -> Dictionary:
	return {"ok": false, "verb": verb, "station": station_id, "item": item,
			"result": "", "say": say, "gesture": ""}
