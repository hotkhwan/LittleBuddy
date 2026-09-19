extends RefCounted

## The HUD must go quiet under a close-up — but never take the way out with it.
##
## Found by photographing the feeding beat at a TRUE 2340x1080 iPhone viewport.
## The care overlay names the act ("Drink!"), gives the hint ("Hold the bottle at
## Bunny's mouth.") and shows its own progress. Underneath it the HUD was drawing
## the same two things again — "Give Bunny the bottle." plus the Thai hint — and
## at 2.17 aspect the overlay title and the HUD instruction landed on the same
## pixels and overprinted each other.
##
## It only showed up at that aspect. Every earlier "iPhone" screenshot in this
## repo was silently clamped to 1.80 by the window manager, where the lines
## happen to miss each other. That is why the size assertion in
## `tests/shots_rc.gd` exists.
##
## THE HALF THAT MATTERS MOST is the second test below. Suppressing narration is
## easy; suppressing the Next button with it would be a dead end, and `CLAUDE.md`
## bans those outright. A child who cannot finish a close-up and cannot leave it
## is stuck in the game with no way forward.

const HudScript := preload("res://scripts/gameplay/house_hud.gd")


func test_name() -> String:
	return "hud_narration_cover"


func run():
	var failures: Array = []
	failures.append_array(_test_narration_goes_quiet())
	failures.append_array(_test_the_way_out_never_goes_with_it())
	failures.append_array(_test_it_comes_back())
	failures.append_array(_test_it_is_idempotent())
	return failures


func _hud() -> Node:
	var hud: Node = HudScript.new()
	hud.call("build")
	hud.call("set_prompt", "Give Bunny the bottle.", "ดื่มนมกันเถอะ")
	hud.call("configure_progress", 7)
	return hud


func _test_narration_goes_quiet():
	var failures: Array = []
	var hud: Node = _hud()
	hud.call("set_narration_covered", true)
	if not bool(hud.call("is_narration_covered")):
		failures.append("the HUD does not report itself covered")
	var prompt: Node = hud.find_child("Prompt", true, false)
	if prompt != null and bool(prompt.get("visible")):
		failures.append("the instruction is still drawn under the close-up, which is "
				+ "what overprinted the overlay's own title at 2.17 aspect")
	hud.free()
	return failures


## The one that must never regress.
func _test_the_way_out_never_goes_with_it():
	var failures: Array = []
	var hud: Node = _hud()
	hud.call("set_skip_visible", true)
	hud.call("set_narration_covered", true)
	if not bool(hud.call("is_skip_visible")):
		failures.append("covering the narration hid the Next button. That is a DEAD END: "
				+ "a child who cannot finish the close-up and cannot leave it is stuck "
				+ "in the game, which CLAUDE.md bans outright.")
	hud.free()
	return failures


func _test_it_comes_back():
	var failures: Array = []
	var hud: Node = _hud()
	hud.call("set_narration_covered", true)
	hud.call("set_narration_covered", false)
	if bool(hud.call("is_narration_covered")):
		failures.append("the HUD stayed covered after the close-up closed")
	var prompt: Node = hud.find_child("Prompt", true, false)
	if prompt != null and not bool(prompt.get("visible")):
		failures.append("the instruction did not come back, so the next beat would be silent")
	hud.free()
	return failures


func _test_it_is_idempotent():
	var failures: Array = []
	var hud: Node = _hud()
	for _i in range(3):
		hud.call("set_narration_covered", true)
	for _i in range(3):
		hud.call("set_narration_covered", false)
	if bool(hud.call("is_narration_covered")):
		failures.append("repeated calls did not settle")
	# A care beat that is opened, abandoned and re-opened must not leave the HUD
	# permanently silent.
	hud.call("set_narration_covered", true)
	hud.call("set_narration_covered", true)
	hud.call("set_narration_covered", false)
	var prompt: Node = hud.find_child("Prompt", true, false)
	if prompt != null and not bool(prompt.get("visible")):
		failures.append("two covers and one uncover left the HUD silent for good")
	hud.free()
	return failures
