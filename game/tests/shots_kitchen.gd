extends SceneTree

## PROOF, not a mockup: the cooking activity photographed in the shipping house.
##
##   Godot --path game --resolution 1334x750 --script res://tests/shots_kitchen.gd
##
## The brief rules out unit tests, spike scenes and static mockups as evidence,
## so this drives the REAL `house_world.tscn`, the real kitchen the child walks
## into, and photographs each of the eight steps it asks to see:
##
##   1 open fridge   2 take ingredient   3 carry it   4 place on counter
##   5 prepare       6 transform         7 serve      8 bring it to Bunny
##
## Each shot is taken AFTER the real verb has been applied to the real
## `KitchenState`, and the run fails loudly if a verb is refused -- so a picture
## can never show a step that did not happen.

const OUT_DIR: String = "docs/shots/"
const Rules := preload("res://scripts/kitchen/kitchen_rules.gd")

var _world: Node = null
var _state: RefCounted = null
var _fail: Array = []


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var packed: PackedScene = load("res://scenes/house/house_world.tscn")
	_world = packed.instantiate()
	root.add_child(_world)
	await _settle(0.4)

	if not _world.call("place_in_room", "kitchen", "default"):
		print("FAIL: could not enter the kitchen")
		quit(1)
		return
	await _settle(0.6)

	_state = _world.call("get_kitchen_state")
	if _state == null:
		print("FAIL: the kitchen has no interactive state")
		quit(1)
		return

	await _shot("kitchen_1_arrive", "the kitchen as the child finds it")

	_do(_state.set_open(Rules.STATION_FRIDGE, true), "open the fridge")
	await _shot("kitchen_2_fridge_open", "fridge open, food visible inside")

	_do(_state.take(Rules.STATION_FRIDGE, "banana"), "take the banana")
	await _shot("kitchen_3_take_banana", "banana out of the fridge and in her hands")

	_do(_state.place(Rules.STATION_COUNTER), "put the banana on the counter")
	await _shot("kitchen_4_on_counter", "banana resting on the counter")

	_do(_state.take(Rules.STATION_COUNTER, "spoon"), "pick up the spoon")
	await _shot("kitchen_5_take_spoon", "spoon in hand, banana still on the counter")

	var made: Dictionary = _state.place(Rules.STATION_COUNTER)
	_do(made, "mash the banana")
	if String(made.get("result", "")) != "mashedBanana":
		_fail.append("mashing made '%s'" % String(made.get("result", "")))
	await _shot("kitchen_6_transformed", "two ingredients became one bowl of food")

	_do(_state.take(Rules.STATION_COUNTER, "mashedBanana"), "pick the food up")
	_do(_state.place(Rules.STATION_TABLE), "serve it at the table")
	await _shot("kitchen_7_served", "the food served on the table")

	_do(_state.take(Rules.STATION_TABLE, "mashedBanana"), "carry it to Bunny")
	_world.call("place_in_room", "bedroom", "fromKitchen")
	await _settle(0.8)
	await _shot("kitchen_8_to_bunny", "carried out of the kitchen, to Bunny")
	var fed: Dictionary = _state.give_to_bunny()
	_do(fed, "give the food to Bunny")

	# And the fridge closes again, because a door that only opens is a trick.
	_world.call("place_in_room", "kitchen", "default")
	await _settle(0.5)
	_do(_state.set_open(Rules.STATION_FRIDGE, false), "close the fridge")
	await _shot("kitchen_9_fridge_closed", "fridge closed again")

	if _fail.is_empty():
		print("\nSHOTS OK -- every step happened before it was photographed.")
		quit(0)
	else:
		print("\nSHOTS FAIL:")
		for problem: String in _fail:
			print("  - %s" % problem)
		quit(1)


## Applies a verb and refuses to continue quietly if the kitchen said no.
func _do(report: Dictionary, what: String) -> void:
	if not bool(report.get("ok", false)):
		_fail.append("could not %s: %s" % [what, String(report.get("say", ""))])
	else:
		print("  ok  %-32s -> %s" % [what, String(report.get("say", ""))])


func _shot(name: String, caption: String) -> void:
	await _settle(0.45)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://../" + OUT_DIR + name + ".png")
	var err: int = image.save_png(path)
	print("  %s %s.png  (%s)" % ["shot" if err == OK else "FAIL", name, caption])
	if err != OK:
		_fail.append("could not write %s.png" % name)


func _settle(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
