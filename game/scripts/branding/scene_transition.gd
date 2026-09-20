class_name SceneTransition
extends CanvasLayer

## A soft cream curtain with a tiny heart, for the moment between two scenes.
##
## ```gdscript
## const SceneTransition := preload("res://scripts/branding/scene_transition.gd")
##
## await SceneTransition.cover(get_tree())          # 0.35 s: cream fades in, heart pops
## get_tree().change_scene_to_file(NEXT_SCENE)        # happens behind the curtain
## # nothing else to do: the curtain notices the new scene and lifts itself,
## # 0.35 s, then frees itself. Or lift it by hand:
## SceneTransition.reveal_current(get_tree())
## ```
##
## ## What it promises
##
##   * **No autoload.** `cover()` adds one `CanvasLayer` under the tree root, on
##     a layer above every HUD, and that node removes itself when it is done.
##     Nothing about it survives the transition.
##   * **Never traps.** A curtain that is covered and has not been told to lift
##     lifts itself once the current scene changes, and in any case after
##     `HOLD_TIMEOUT` seconds. There is no state in which a child is left looking
##     at a cream screen because a caller forgot the second half.
##   * **One at a time.** A second `cover()` while one is up returns the existing
##     curtain's signal instead of stacking a second one.
##   * **Deterministic.** The animation is driven from `_process(delta)` rather
##     than a `Tween`, so `test_branding_transition.gd` can step it by hand in
##     the headless runner and prove it completes and frees itself.
##
## ## Why cream, not black
##
## The art bible: pure black in a pastel scene reads as a hole punched in the
## picture. The curtain is `Palette.CREAM` warmed a step toward `PEACH`, which
## is the same family as the boot splash and the loading scene, so the whole
## start-up reads as one continuous surface.

signal covered
signal revealed

const Palette := preload("res://scripts/ui/palette.gd")

## Where `cover()` finds this script from inside a static function.
const SCRIPT_PATH: String = "res://scripts/branding/scene_transition.gd"

const DURATION_IN: float = 0.35
const DURATION_OUT: float = 0.35
## Covered and nobody lifted the curtain: lift it anyway.
const HOLD_TIMEOUT: float = 2.5
## Above every HUD `CanvasLayer` in the project (they use 0..10).
const LAYER_INDEX: int = 120
const NODE_NAME: String = "SceneTransition"

enum Phase { IDLE, COVERING, HOLDING, REVEALING, DONE, DRIVEN }

var _phase: int = Phase.IDLE
var _progress: float = 0.0
var _hold_elapsed: float = 0.0
var _scene_at_cover: Node = null
var _curtain: ColorRect = null
var _heart: Control = null
var _heart_time: float = 0.0


# --- Static entry points --------------------------------------------------------


## Puts the curtain up over `tree`. Returns the `covered` signal so the caller
## can `await` it before swapping scenes. If a curtain is already up, returns
## that one's signal (already emitted or not) rather than stacking another.
static func cover(tree: SceneTree) -> Signal:
	var existing: CanvasLayer = current(tree)
	if existing != null:
		return Signal(existing, "covered")
	var script: GDScript = load(SCRIPT_PATH)
	var node: CanvasLayer = script.new()
	node.name = NODE_NAME
	tree.root.add_child(node)
	node.call("_begin_cover", tree.current_scene)
	return Signal(node, "covered")


## Lifts whichever curtain is up. False when there is none.
static func reveal_current(tree: SceneTree) -> bool:
	var existing: CanvasLayer = current(tree)
	if existing == null:
		return false
	existing.call("reveal")
	return true


## The curtain currently up over `tree`, or null.
static func current(tree: SceneTree) -> CanvasLayer:
	if tree == null or tree.root == null:
		return null
	var node: Node = tree.root.get_node_or_null(NodePath(NODE_NAME))
	if node is CanvasLayer and node.get_script() == load(SCRIPT_PATH):
		if int(node.get("_phase")) != Phase.DONE:
			return node
	return null


# --- Instance API -----------------------------------------------------------------


## Starts the fade-out. Returns `revealed`, emitted just before the node frees
## itself. Safe to call more than once and safe to call while still covering
## (the reveal starts from wherever the cover got to).
func reveal() -> Signal:
	if _phase == Phase.COVERING or _phase == Phase.HOLDING:
		_phase = Phase.REVEALING
	return revealed


func is_covered() -> bool:
	return _phase == Phase.HOLDING


## DRIVEN mode: a caller with its own timeline (the menu's walk-home departure)
## moves the curtain itself with `set_progress()`. Reaching 1.0 hands over to
## the normal HOLDING phase, so the auto-lift when the scene changes still
## applies and nobody has to remember to reveal.
func begin_driven(scene_at_cover: Node) -> void:
	_scene_at_cover = scene_at_cover
	_phase = Phase.DRIVEN
	_progress = 0.0
	set_process(true)
	_apply()


func set_progress(value: float) -> void:
	if _phase != Phase.DRIVEN:
		return
	_progress = clampf(value, 0.0, 1.0)
	_apply()
	if _progress >= 1.0:
		_phase = Phase.HOLDING
		_hold_elapsed = 0.0
		covered.emit()


func get_phase() -> int:
	return _phase


## 0..1 opacity of the curtain, for tests and for anyone drawing under it.
func get_opacity() -> float:
	return _progress


# --- Lifecycle --------------------------------------------------------------------


func _init() -> void:
	layer = LAYER_INDEX
	_build()


func _build() -> void:
	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.color = Palette.CREAM.lerp(Palette.PEACH, 0.35)
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Eats taps while it is up: a half-faded button must not fire.
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	_curtain.modulate.a = 0.0
	add_child(_curtain)

	_heart = HeartMark.new()
	_heart.name = "Heart"
	_heart.set_anchors_preset(Control.PRESET_CENTER)
	_heart.size = Vector2(96, 96)
	_heart.position = -_heart.size * 0.5
	_heart.pivot_offset = _heart.size * 0.5
	_heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heart.scale = Vector2.ZERO
	_curtain.add_child(_heart)


func _begin_cover(scene_at_cover: Node) -> void:
	_scene_at_cover = scene_at_cover
	_phase = Phase.COVERING
	_progress = 0.0
	set_process(true)


func _process(delta: float) -> void:
	match _phase:
		Phase.COVERING:
			_progress = minf(1.0, _progress + delta / DURATION_IN)
			_apply()
			if _progress >= 1.0:
				_phase = Phase.HOLDING
				_hold_elapsed = 0.0
				covered.emit()
		Phase.HOLDING:
			_hold_elapsed += delta
			_heart_time += delta
			_apply()
			var tree: SceneTree = get_tree() if is_inside_tree() else Engine.get_main_loop() as SceneTree
			var scene_changed: bool = tree != null and tree.current_scene != _scene_at_cover \
					and tree.current_scene != null
			if scene_changed or _hold_elapsed >= HOLD_TIMEOUT:
				_phase = Phase.REVEALING
		Phase.DRIVEN:
			_heart_time += delta
			_apply()
		Phase.REVEALING:
			_progress = maxf(0.0, _progress - delta / DURATION_OUT)
			_apply()
			if _progress <= 0.0:
				_phase = Phase.DONE
				set_process(false)
				revealed.emit()
				queue_free()
		_:
			pass


func _apply() -> void:
	var eased: float = smoothstep(0.0, 1.0, _progress)
	_curtain.modulate.a = eased
	# The heart pops in a beat after the curtain, then breathes while holding.
	var heart_t: float = clampf((_progress - 0.35) / 0.65, 0.0, 1.0)
	var pop: float = 1.0 - pow(1.0 - heart_t, 3.0)
	var breathe: float = 1.0 + 0.06 * sin(_heart_time * 4.0)
	_heart.scale = Vector2.ONE * pop * breathe
	_heart.rotation = deg_to_rad(-8.0 * (1.0 - pop))


## A small soft-pink heart, drawn rather than loaded so the curtain has no
## texture dependency and can never show a missing-asset placeholder.
class HeartMark extends Control:
	func _draw() -> void:
		var points := PackedVector2Array()
		var centre: Vector2 = size * 0.5
		var radius: float = size.x * 0.028
		for i in range(48):
			var t: float = TAU * float(i) / 48.0
			var x: float = 16.0 * pow(sin(t), 3.0)
			var y: float = -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
			points.append(centre + Vector2(x, y) * radius)
		draw_colored_polygon(points, Palette.SOFT_PINK)
		# A single highlight keeps it "toy", not "sticker".
		draw_circle(centre + Vector2(-radius * 6.0, -radius * 6.5), radius * 2.4, Palette.CREAM)
