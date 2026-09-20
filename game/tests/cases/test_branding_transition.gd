extends RefCounted

## The cream curtain between scenes completes, lifts itself, and frees itself.
##
## `scene_transition.gd` is the one piece of chrome that sits ABOVE every scene
## and outlives the scene that created it. If it ever stalls, the child is
## looking at a cream screen with a heart on it and nothing responds -- so the
## contract pinned here is the "never traps" one:
##
##   * `cover()` reaches `covered` in `DURATION_IN` seconds and eats input while
##     it is up;
##   * `reveal()` reaches `revealed` in `DURATION_OUT` seconds and the node
##     queues itself for deletion;
##   * a curtain nobody lifts lifts itself once the current scene changes, and
##     after `HOLD_TIMEOUT` seconds regardless;
##   * a second `cover()` while one is up does not stack a second curtain;
##   * the curtain paints no black.
##
## Driven by calling `_process()` by hand, which is why the component animates
## from `_process` rather than a `Tween`: the runner never yields a frame.

const Transition := preload("res://scripts/branding/scene_transition.gd")
const Palette := preload("res://scripts/ui/palette.gd")

const STEP: float = 0.05


func test_name() -> String:
	return "branding_transition"


func run():
	var failures: Array = []
	failures.append_array(_test_cover_then_reveal_completes_and_frees())
	failures.append_array(_test_unlifted_curtain_lifts_itself())
	failures.append_array(_test_cover_twice_is_one_curtain())
	failures.append_array(_test_curtain_is_not_black())
	return failures


func _test_cover_then_reveal_completes_and_frees():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree in the runner"]
	_sweep(tree)

	var covered_signal: Signal = Transition.cover(tree)
	var curtain: Node = Transition.current(tree)
	if curtain == null:
		return ["cover() put no curtain under the tree root"]
	if curtain.get_parent() != tree.root:
		failures.append("the curtain is not a child of the tree root; a scene change would free it")
	if not (curtain is CanvasLayer):
		failures.append("the curtain is not a CanvasLayer; it would sit under a HUD instead of over it")

	var got: Dictionary = {"covered": 0, "revealed": 0}
	covered_signal.connect(func() -> void: got["covered"] += 1)
	curtain.connect("revealed", func() -> void: got["revealed"] += 1)

	# Cover: 0.35 s of steps, plus a hair, and it must be fully opaque.
	var steps: int = int(ceil(Transition.DURATION_IN / STEP)) + 1
	for _i in range(steps):
		curtain.call("_process", STEP)
	if got["covered"] != 1:
		failures.append("after %.2f s `covered` fired %d times; expected exactly once"
				% [steps * STEP, got["covered"]])
	if not bool(curtain.call("is_covered")):
		failures.append("after the cover time the curtain does not report is_covered()")
	if absf(float(curtain.call("get_opacity")) - 1.0) > 0.001:
		failures.append("covered but opacity is %.3f, not 1" % float(curtain.call("get_opacity")))
	var rect: Control = curtain.get_node_or_null("Curtain")
	if rect == null:
		failures.append("no Curtain ColorRect to eat taps")
	elif rect.mouse_filter != Control.MOUSE_FILTER_STOP:
		failures.append("the curtain lets taps through while it is up")

	# Reveal: 0.35 s later it is gone.
	curtain.call("reveal")
	steps = int(ceil(Transition.DURATION_OUT / STEP)) + 1
	for _i in range(steps):
		curtain.call("_process", STEP)
	if got["revealed"] != 1:
		failures.append("after %.2f s `revealed` fired %d times; expected exactly once"
				% [steps * STEP, got["revealed"]])
	if not curtain.is_queued_for_deletion():
		failures.append("revealed but the curtain did not queue_free() itself")
	if Transition.current(tree) != null:
		failures.append("a finished curtain still reports as current(); the next cover() would reuse a corpse")
	_sweep(tree)
	return failures


func _test_unlifted_curtain_lifts_itself():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree in the runner"]
	_sweep(tree)
	Transition.cover(tree)
	var curtain: Node = Transition.current(tree)
	if curtain == null:
		return ["cover() put no curtain under the tree root"]
	var total: float = Transition.DURATION_IN + Transition.HOLD_TIMEOUT + Transition.DURATION_OUT + 0.2
	var elapsed: float = 0.0
	while elapsed < total and not curtain.is_queued_for_deletion():
		curtain.call("_process", STEP)
		elapsed += STEP
	if not curtain.is_queued_for_deletion():
		failures.append("a curtain nobody lifted was still up after %.1f s; that is a trap" % total)
	# It must not lift EARLY either: the hold exists so the caller has time to swap.
	if elapsed < Transition.DURATION_IN + Transition.HOLD_TIMEOUT - STEP:
		failures.append("the curtain lifted itself after %.2f s, before HOLD_TIMEOUT" % elapsed)
	_sweep(tree)
	return failures


func _test_cover_twice_is_one_curtain():
	var failures: Array = []
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ["no SceneTree in the runner"]
	_sweep(tree)
	var first: Signal = Transition.cover(tree)
	var second: Signal = Transition.cover(tree)
	if first.get_object_id() != second.get_object_id():
		failures.append("cover() twice made two curtains; the second call must return the first's signal")
	var count: int = 0
	for child: Node in tree.root.get_children():
		if child.name == Transition.NODE_NAME:
			count += 1
	if count != 1:
		failures.append("%d curtains under the root after two cover() calls" % count)
	if not Transition.reveal_current(tree):
		failures.append("reveal_current() found nothing to lift while a curtain was up")
	_sweep(tree)
	if Transition.reveal_current(tree):
		failures.append("reveal_current() claims to lift a curtain when there is none")
	return failures


func _test_curtain_is_not_black():
	var failures: Array = []
	var curtain: CanvasLayer = Transition.new()
	var rect: ColorRect = curtain.get_node_or_null("Curtain")
	if rect == null:
		failures.append("no Curtain ColorRect")
	else:
		if Palette.is_black(rect.color):
			failures.append("the curtain is black; the art bible calls that a hole in the picture")
		if rect.color.v < 0.85:
			failures.append("the curtain is dark (v=%.2f); it should be cream" % rect.color.v)
	if curtain.get_node_or_null("Curtain/Heart") == null:
		failures.append("no heart on the curtain")
	curtain.free()
	return failures


## Remove any curtain a previous step left under the root, whatever its state,
## so each step starts clean and nothing leaks into the cases after this one.
func _sweep(tree: SceneTree) -> void:
	for child: Node in tree.root.get_children():
		if child.name == Transition.NODE_NAME:
			tree.root.remove_child(child)
			child.free()
