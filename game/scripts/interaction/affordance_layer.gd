extends Control

## Proximity affordances: when Aliz is close to something she can act on, a
## big colourful badge appears over it saying what -- OPEN, TAKE, PLACE, ENTER,
## HUG, CARRY, FEED -- and tapping the badge does it.
##
## ## Why
##
## Playtested cold, the house asked a four-year-old to aim a fingertip at a
## fridge handle 40 px wide and to know, unprompted, that the fridge was the
## thing to press. Neither is fair. The badge is a 240 px tap target with a
## picture on it, placed by the game, and it only exists while the child is near
## enough for the action to make sense -- which is also how it teaches the word.
##
## ## The contract (shared with every other agent)
##
## Every frame this polls the `affordable` group. Any node in it exposes
##
##     get_affordance(actor: Node3D) -> Dictionary
##
## returning `{}` when nothing applies, else `{"verb", "anchor", "radius",
## "priority", "target"}` (`targetId` and `extent` optional). Nothing here knows
## what a fridge, a door or Bunny is. A tap on the badge calls
## `perform_affordance(actor) -> bool` on the target if it has one and it returns
## true; otherwise the tap falls through to the ordinary routing
## (`NavigationController.apply_tap`), so Aliz walks over exactly as if the object
## itself had been tapped, and whatever already happens on arrival happens.
##
## `ActivityTarget` implements the read half for every door and piece of
## furniture, and takes a context provider for the state it cannot see (is the
## fridge open, what is in the hand); `_default_context()` here supplies it from
## the kitchen and the room's storages, duck-typed and guarded, so a world
## without a kitchen still gets ENTER on its doors.
##
## ## Cheap
##
## One `unproject_position()` and one `_draw()` of a dozen primitives per frame,
## one hit-test `Control`. No 3D node, no material, no light.
##
## ## Headless
##
## `step(delta)` is public and `_process()` only forwards to it. Candidates can
## be supplied directly (`set_candidate_sources()`) so the rules run without a
## tree, and with no camera the badge is simply not laid out.

const AffordanceRules := preload("res://scripts/interaction/affordance_rules.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")

const GROUP: String = "affordable"

## ART_BIBLE §8: a child's tap target is at least 240 px across at the
## 1366x1024 reference. The drawn disc is smaller; the invisible hit box is not.
const HIT_SIZE: float = 240.0
const BADGE_RADIUS: float = 74.0
const OUTLINE_PX: float = 5.0
## How far above the object's highlight ring the badge floats.
const BADGE_LIFT: float = 62.0
const EDGE_MARGIN: float = 26.0
## The top band nothing may sit in unless the HUD says otherwise: the star
## counter and the Home button live there. `set_top_keep_out()` raises it while
## a prompt is on screen.
const TOP_MARGIN: float = 40.0
## The corners are taken (stars top-left, Home top-right): a badge that would
## land this close to the top is pushed under them at the sides.
const CORNER_BAND: float = 132.0
const CORNER_LEFT: float = 280.0
const CORNER_RIGHT: float = 160.0
## Gap between the highlight ring and a badge placed beside it.
const SIDE_GAP: float = 28.0

## The word under the picture. 28 pt clears the §8 floor of 27.
const LABEL_FONT_SIZE: int = 28
const LABEL_WIDTH: float = 156.0
const LABEL_HEIGHT: float = 42.0
const LABEL_GAP: float = 14.0

## The highlight ring around the thing itself, px, clamped so a fridge across
## the room and a table under the camera both get a ring you can see.
const RING_MIN_PX: float = 44.0
const RING_MAX_PX: float = 210.0
const RING_WIDTH: float = 7.0
const DEFAULT_EXTENT_M: float = 0.35

## `NavigationController.TapKind.TARGET`. Mirrored rather than imported so this
## layer never depends on the router parsing; `test_affordance.gd` pins the two.
const TAP_KIND_TARGET: int = 1

const PRESS_SEC: float = 0.22

signal affordance_shown(verb: String, target_id: String)
signal affordance_hidden()
signal affordance_performed(verb: String, target_id: String, handled_by_target: bool)

var _built: bool = false
var _enabled: bool = true
var _world: Node = null
var _actor: Node3D = null
var _camera: Camera3D = null
var _nav: Node = null
## Overrides `_default_context()` when valid: `func(target, actor) -> Dictionary`.
var _context_provider: Callable = Callable()
## Nodes to poll INSTEAD of the tree group. Tests, and any host that prefers
## to hand the layer its candidates.
var _candidate_sources: Array = []
var _preferred_ids: Array = []
var _auto_preferred: bool = true
var _top_keep_out: float = TOP_MARGIN
## Where the badge ended up relative to the ring: "above", "left" or "right".
var _placement: String = "above"
## Instance ids of targets this layer has already given its context provider.
var _provided: Dictionary = {}

var _current: Dictionary = {}
var _shown_key: String = ""
var _screen: Vector2 = Vector2.ZERO
var _badge: Vector2 = Vector2.ZERO
var _ring_px: float = RING_MIN_PX
var _laid_out: bool = false
var _clock: float = 0.0
var _press_clock: float = -1.0

var _hit: Control = null
var _pill: StyleBoxFlat = null
var _font: Font = null


func _ready() -> void:
	build()
	set_process(true)


## Idempotent, and called from every public method: `_ready()` never fires for
## a node added to the root in the headless runner.
func build() -> void:
	if _built:
		return
	_built = true
	name = "AffordanceLayer"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hit = Control.new()
	_hit.name = "AffordanceHit"
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.focus_mode = Control.FOCUS_NONE
	_hit.size = Vector2(HIT_SIZE, HIT_SIZE)
	_hit.visible = false
	_hit.gui_input.connect(_on_hit_input)
	add_child(_hit)

	_pill = StyleBoxFlat.new()
	_pill.bg_color = Palette.CREAM
	_pill.border_color = Palette.INK
	_pill.set_border_width_all(3)
	_pill.set_corner_radius_all(int(LABEL_HEIGHT * 0.5))
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	step(delta)


## -- Wiring --------------------------------------------------------------------

## Joins the layer to a world. Duck-typed: `get_character()` for the actor,
## a `NavigationController` child for the fall-through routing, and the camera
## is read live from the viewport because the room camera is adopted later.
func bind(world: Node) -> void:
	build()
	_world = world
	if _world == null:
		return
	if _world.has_method("get_character"):
		var actor: Variant = _world.call("get_character")
		if actor is Node3D:
			_actor = actor
	_nav = _world.get_node_or_null("NavigationController")


func set_actor(actor: Node3D) -> void:
	build()
	_actor = actor


func set_camera(camera: Camera3D) -> void:
	build()
	_camera = camera


func set_navigation_controller(nav: Node) -> void:
	build()
	_nav = nav


## `provider` is `func(target: Node, actor: Node3D) -> Dictionary`. Replaces the
## built-in kitchen/storage context for every target this layer polls.
func set_context_provider(provider: Callable) -> void:
	build()
	_context_provider = provider


## Poll these nodes instead of the `affordable` group. Empty restores the group.
func set_candidate_sources(sources: Array) -> void:
	build()
	_candidate_sources = sources.duplicate()


## Which semantic ids the current mission beat is about. When `auto` is left
## on, the layer reads them from the world's level director each frame instead.
func set_preferred_target_ids(ids: Array, auto: bool = false) -> void:
	build()
	_preferred_ids = ids.duplicate()
	_auto_preferred = auto


## The top `px` of the screen belong to somebody else (the HUD's prompt band).
## The badge is placed below that line, beside the object if need be.
func set_top_keep_out(px: float) -> void:
	build()
	_top_keep_out = maxf(px, TOP_MARGIN)


func get_top_keep_out() -> float:
	return _top_keep_out


## Off while a menu, a summary or a close-up owns the screen.
func set_enabled(value: bool) -> void:
	build()
	_enabled = value
	if not value:
		_current = {}
		_layout()
		_announce()
		queue_redraw()


func is_enabled() -> bool:
	return _enabled


## -- Per frame -----------------------------------------------------------------

func step(delta: float) -> void:
	build()
	_clock += maxf(delta, 0.0)
	if _press_clock >= 0.0:
		_press_clock += maxf(delta, 0.0)
		if _press_clock > PRESS_SEC:
			_press_clock = -1.0
	_current = evaluate()
	_layout()
	_announce()
	queue_redraw()


## The offer the child should see right now, or `{}`. Pure apart from reading
## the candidates: no camera and no viewport are involved.
func evaluate() -> Dictionary:
	build()
	if not _enabled:
		return {}
	if _actor == null or not is_instance_valid(_actor):
		return {}
	if _nav != null and is_instance_valid(_nav) and _nav.get("taps_enabled") != null \
			and not bool(_nav.get("taps_enabled")):
		return {}
	if _actor.has_method("get_state_name") and String(_actor.call("get_state_name")) == "disabled":
		return {}
	var here: Vector3 = SpatialUtil.world_position(_actor)
	return AffordanceRules.pick(_candidates(), here, _preferred_now())


func _candidates() -> Array:
	var sources: Array = _candidate_sources
	if sources.is_empty():
		if not is_inside_tree():
			return []
		var tree: SceneTree = get_tree()
		if tree == null:
			return []
		sources = tree.get_nodes_in_group(GROUP)
	var offers: Array = []
	for node: Variant in sources:
		if not (node is Object) or not is_instance_valid(node):
			continue
		var candidate: Object = node
		if not candidate.has_method("get_affordance"):
			continue
		_provide_context(candidate)
		var offer: Variant = candidate.call("get_affordance", _actor)
		if not (offer is Dictionary) or (offer as Dictionary).is_empty():
			continue
		var entry: Dictionary = offer
		if not entry.has("targetId") and candidate.has_method("get_activity_target_id"):
			entry["targetId"] = String(candidate.call("get_activity_target_id"))
		if not entry.has("target"):
			entry["target"] = candidate
		offers.append(entry)
	return offers


## Hands a target the context callback once. The target keeps it; the layer
## keeps only the instance id so a freed node never gets touched again.
func _provide_context(candidate: Object) -> void:
	if not candidate.has_method("set_affordance_context_provider"):
		return
	var id: int = candidate.get_instance_id()
	if _provided.has(id):
		return
	_provided[id] = true
	candidate.call("set_affordance_context_provider", Callable(self, "context_for"))


## The `context` half of `AffordanceRules.verb_for_target()` for `target`.
## Public so a test can ask it directly.
func context_for(target: Object, actor: Node3D) -> Dictionary:
	if _context_provider.is_valid():
		var supplied: Variant = _context_provider.call(target, actor)
		if supplied is Dictionary:
			return supplied
		return {}
	return _default_context(target)


## The kitchen and the room's containers, read duck-typed off the world. A
## world with neither gives `{}`, and the target falls back to its own action
## list.
func _default_context(target: Object) -> Dictionary:
	var context: Dictionary = {}
	if _world == null or not is_instance_valid(_world):
		return context
	var local_id: String = ""
	if target.has_method("get_local_target_id"):
		local_id = String(target.call("get_local_target_id"))
	if local_id.is_empty():
		return context

	if _world.has_method("get_kitchen_state"):
		var kitchen: Variant = _world.call("get_kitchen_state")
		if kitchen is Object and is_instance_valid(kitchen) and kitchen.has_method("describe") \
				and kitchen.has_method("held"):
			var held: String = String(kitchen.call("held"))
			context["held"] = held
			var described: Dictionary = kitchen.call("describe", local_id)
			if not String(described.get("role", "")).is_empty():
				context["station"] = _station_context(local_id, described, held)

	if not context.has("station") and _world.has_method("get_current_room"):
		var room: Variant = _world.call("get_current_room")
		if room is Object and is_instance_valid(room) and room.has_method("get_storage") \
				and room.call("get_storage", local_id) != null:
			var is_open: bool = false
			if room.has_method("is_storage_open"):
				is_open = bool(room.call("is_storage_open", local_id))
			context["storage"] = {"isOpen": is_open}
	return context


func _station_context(station_id: String, described: Dictionary, held: String) -> Dictionary:
	var opens: bool = false
	var can_place: bool = false
	var rules_path: String = "res://scripts/kitchen/kitchen_rules.gd"
	if ResourceLoader.exists(rules_path):
		var rules: GDScript = load(rules_path)
		if rules != null:
			opens = bool(rules.opens(station_id))
			var resting: String = String(described.get("on", AffordanceRules.NONE))
			if AffordanceRules.is_nothing(resting):
				resting = AffordanceRules.NONE
			if not AffordanceRules.is_nothing(held):
				can_place = bool(rules.can_place(station_id, held, resting)) \
						or not AffordanceRules.is_nothing(rules.combination(station_id, resting, held))
	return {
		"opens": opens,
		"isOpen": bool(described.get("open", false)),
		"inside": described.get("inside", []),
		"on": String(described.get("on", AffordanceRules.NONE)),
		"canPlace": can_place,
	}


func _preferred_now() -> Array:
	if not _auto_preferred:
		return _preferred_ids
	var ids: Array = []
	if _world == null or not is_instance_valid(_world) or not _world.has_method("get_level_director"):
		return ids
	var director: Variant = _world.call("get_level_director")
	if not (director is Object) or not is_instance_valid(director) \
			or not director.has_method("get_current_plan"):
		return ids
	var plan: Dictionary = director.call("get_current_plan")
	for key: String in ["walkTargetId", "focusTargetId"]:
		var id: String = String(plan.get(key, ""))
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
	return ids


func _camera_now() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	if not is_inside_tree():
		return null
	var viewport: Viewport = get_viewport()
	return viewport.get_camera_3d() if viewport != null else null


## Places the badge and the hit box for `_current`. With no camera nothing is
## placed and the hit box hides, so a headless world can never be tapped.
func _layout() -> void:
	_laid_out = false
	if _current.is_empty():
		_hit.visible = false
		return
	var camera: Camera3D = _camera_now()
	if camera == null:
		_hit.visible = false
		return
	var anchor: Vector3 = _current["anchor"]
	if camera.is_position_behind(anchor):
		_hit.visible = false
		return
	_screen = camera.unproject_position(anchor)
	var extent: float = float(_current.get("extent", DEFAULT_EXTENT_M))
	var basis: Basis = SpatialUtil.world_transform(camera).basis
	var edge: Vector2 = camera.unproject_position(anchor + basis.x * maxf(extent, 0.05))
	_ring_px = clampf((edge - _screen).length(), RING_MIN_PX, RING_MAX_PX)

	var view: Vector2 = get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		view = size
	var min_x: float = EDGE_MARGIN + BADGE_RADIUS + OUTLINE_PX
	var max_x: float = view.x - min_x
	var min_y: float = _top_keep_out + BADGE_RADIUS
	var max_y: float = view.y - (EDGE_MARGIN + BADGE_RADIUS + LABEL_GAP + LABEL_HEIGHT)

	# Above the thing, by preference. When the top of the screen is spoken for
	# -- the prompt band, or the object is simply high in the frame, as a fridge
	# is -- the badge steps BESIDE the ring instead of dropping onto whatever is
	# in front of the object, which is Aliz's face more often than not. The
	# side is the one away from her.
	var wanted: Vector2 = _screen + Vector2(0.0, -(_ring_px + BADGE_LIFT + BADGE_RADIUS))
	_placement = "above"
	if wanted.y < min_y:
		var side: float = -1.0 if _screen.x > view.x * 0.5 else 1.0
		var actor_x: float = _actor_screen_x(camera)
		if actor_x > _screen.x + 8.0:
			side = -1.0
		elif actor_x < _screen.x - 8.0:
			side = 1.0
		wanted = _screen + Vector2(side * (_ring_px + SIDE_GAP + BADGE_RADIUS), -BADGE_RADIUS * 0.4)
		_placement = "left" if side < 0.0 else "right"
	_badge = Vector2(clampf(wanted.x, min_x, maxf(min_x, max_x)),
			clampf(wanted.y, min_y, maxf(min_y, max_y)))
	# The corners are taken: stars top-left, Home top-right.
	if _badge.y - BADGE_RADIUS < CORNER_BAND \
			and (_badge.x - BADGE_RADIUS < CORNER_LEFT or _badge.x + BADGE_RADIUS > view.x - CORNER_RIGHT):
		_badge.y = minf(CORNER_BAND + BADGE_RADIUS, maxf(min_y, max_y))
	_hit.position = _badge - Vector2(HIT_SIZE, HIT_SIZE) * 0.5
	_hit.visible = true
	_laid_out = true


func _actor_screen_x(camera: Camera3D) -> float:
	if _actor == null or not is_instance_valid(_actor):
		return _screen.x
	var chest: Vector3 = SpatialUtil.world_position(_actor) + Vector3(0.0, 0.8, 0.0)
	if camera.is_position_behind(chest):
		return _screen.x
	return camera.unproject_position(chest).x


func get_placement() -> String:
	return _placement


func _announce() -> void:
	var key: String = ""
	if not _current.is_empty():
		key = "%s|%s" % [String(_current.get("verb", "")), String(_current.get("targetId", ""))]
	if key == _shown_key:
		return
	_shown_key = key
	if key.is_empty():
		affordance_hidden.emit()
	else:
		affordance_shown.emit(String(_current["verb"]), String(_current.get("targetId", "")))


## -- Tap -----------------------------------------------------------------------

func _on_hit_input(event: InputEvent) -> void:
	var pressed: bool = false
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		pressed = mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	perform()
	accept_event()


## Does the shown affordance. Returns whether anything was asked to happen.
func perform() -> bool:
	build()
	if _current.is_empty():
		return false
	var verb: String = String(_current.get("verb", ""))
	var target_id: String = String(_current.get("targetId", ""))
	var target: Variant = _current.get("target", null)
	_press_clock = 0.0

	if target is Object and is_instance_valid(target) and target.has_method("perform_affordance"):
		if bool(target.call("perform_affordance", _actor)):
			affordance_performed.emit(verb, target_id, true)
			return true

	var routed: bool = false
	if not target_id.is_empty():
		if _nav != null and is_instance_valid(_nav) and _nav.has_method("apply_tap"):
			routed = bool(_nav.call("apply_tap", {
				"kind": TAP_KIND_TARGET, "targetId": target_id, "x": 0.0, "z": 0.0, "reason": "",
			}))
		elif _actor != null and is_instance_valid(_actor) and _actor.has_method("move_to"):
			routed = bool(_actor.call("move_to", target_id))
	affordance_performed.emit(verb, target_id, false)
	return routed


## -- Reading -------------------------------------------------------------------

func is_showing() -> bool:
	return not _current.is_empty()


func get_current() -> Dictionary:
	return _current.duplicate()


func get_current_verb() -> String:
	return String(_current.get("verb", ""))


func get_current_target_id() -> String:
	return String(_current.get("targetId", ""))


## Where the badge is drawn, viewport px. Meaningful only after a laid-out step.
func get_badge_centre() -> Vector2:
	return _badge


func is_laid_out() -> bool:
	return _laid_out


func get_hit_rect() -> Rect2:
	build()
	return Rect2(_hit.position, _hit.size) if _hit.visible else Rect2()


func get_clock() -> float:
	return _clock


## -- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if _current.is_empty() or not _laid_out:
		return
	var verb: String = String(_current.get("verb", ""))
	var tint: Color = AffordanceRules.verb_color(verb)
	var pulse: float = 0.5 + 0.5 * sin(_clock * TAU * 0.6)

	# The thing itself: a ring in the verb's colour, breathing at the art
	# bible's 0.6 Hz, with a faint cream halo so it reads on any wall.
	draw_arc(_screen, _ring_px + 10.0 + pulse * 6.0, 0.0, TAU, 56,
			Color(Palette.CREAM.r, Palette.CREAM.g, Palette.CREAM.b, 0.16 + pulse * 0.12), RING_WIDTH + 6.0, true)
	draw_arc(_screen, _ring_px + pulse * 5.0, 0.0, TAU, 56,
			Color(tint.r, tint.g, tint.b, 0.62 + pulse * 0.28), RING_WIDTH, true)
	draw_arc(_screen, _ring_px + pulse * 5.0, 0.0, TAU, 56,
			Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.22), 2.0, true)

	# The badge bobs gently so it reads as alive, and squashes on a press.
	var bob: float = sin(_clock * TAU * 0.9) * 4.0
	var scale: float = 1.0
	if _press_clock >= 0.0:
		var t: float = clampf(_press_clock / PRESS_SEC, 0.0, 1.0)
		scale = 1.0 - 0.12 * sin(t * PI)
	var centre: Vector2 = _badge + Vector2(0.0, bob)
	var radius: float = BADGE_RADIUS * scale

	# Pointer tail towards the object, drawn first so the disc sits on it.
	var towards: Vector2 = Vector2(0.0, 1.0)
	if _placement == "left":
		towards = Vector2(1.0, 0.0)
	elif _placement == "right":
		towards = Vector2(-1.0, 0.0)
	var across: Vector2 = Vector2(-towards.y, towards.x)
	var tail_tip: Vector2 = centre + towards * (radius + 22.0)
	var tail: PackedVector2Array = PackedVector2Array([
		centre + towards * (radius - 12.0) - across * 20.0,
		centre + towards * (radius - 12.0) + across * 20.0, tail_tip,
	])
	var tail_outline: PackedVector2Array = PackedVector2Array([
		centre + towards * (radius - 14.0) - across * 26.0,
		centre + towards * (radius - 14.0) + across * 26.0,
		tail_tip + towards * 7.0,
	])
	draw_colored_polygon(tail_outline, Palette.INK)
	draw_colored_polygon(tail, tint)

	draw_circle(centre, radius + OUTLINE_PX, Palette.INK)
	draw_circle(centre, radius + OUTLINE_PX - 3.0, Palette.CREAM)
	draw_circle(centre, radius, tint)
	# A soft highlight on the upper left, the way every prop in the house has one.
	draw_circle(centre + Vector2(-radius * 0.34, -radius * 0.38), radius * 0.22,
			Color(Palette.CREAM.r, Palette.CREAM.g, Palette.CREAM.b, 0.55))

	_draw_glyph(verb, centre, radius * 1.18)

	# The word, on a cream pill under the disc.
	var pill: Rect2 = Rect2(
		Vector2(centre.x - LABEL_WIDTH * 0.5, centre.y + radius + LABEL_GAP),
		Vector2(LABEL_WIDTH, LABEL_HEIGHT)
	)
	draw_style_box(_pill, pill)
	if _font != null:
		var baseline: float = pill.position.y + LABEL_HEIGHT * 0.5 \
				+ _font.get_ascent(LABEL_FONT_SIZE) * 0.5 - 3.0
		draw_string(_font, Vector2(pill.position.x, baseline), verb,
				HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, LABEL_FONT_SIZE, Palette.INK)


## One picture per word, all ink strokes on the coloured disc. `box` is the
## square the picture fills; every shape is rounded or a simple arrow.
func _draw_glyph(verb: String, c: Vector2, box: float) -> void:
	var w: float = maxf(box * 0.085, 5.0)
	var ink: Color = Palette.INK
	match verb:
		AffordanceRules.VERB_OPEN:
			# A door ajar: the frame, the leaf swung towards us, a knob, and a
			# little arrow saying which way it goes.
			var frame: Rect2 = Rect2(c + Vector2(-box * 0.30, -box * 0.36), Vector2(box * 0.40, box * 0.70))
			draw_rect(frame, ink, false, w * 0.9)
			var leaf: PackedVector2Array = PackedVector2Array([
				frame.position,
				frame.position + Vector2(box * 0.30, box * 0.08),
				frame.position + Vector2(box * 0.30, frame.size.y - box * 0.08),
				frame.position + Vector2(0.0, frame.size.y),
			])
			draw_colored_polygon(leaf, ink)
			var inner: PackedVector2Array = PackedVector2Array([
				frame.position + Vector2(w * 0.8, w * 0.9),
				frame.position + Vector2(box * 0.30 - w * 0.8, box * 0.08 + w * 0.5),
				frame.position + Vector2(box * 0.30 - w * 0.8, frame.size.y - box * 0.08 - w * 0.5),
				frame.position + Vector2(w * 0.8, frame.size.y - w * 0.9),
			])
			draw_colored_polygon(inner, Palette.CREAM)
			draw_circle(frame.position + Vector2(box * 0.23, frame.size.y * 0.52), w * 0.8, ink)
			draw_arc(c + Vector2(box * 0.12, -box * 0.02), box * 0.24, -PI * 0.55, PI * 0.35, 14, ink, w * 0.8, true)
			_arrow_head(c + Vector2(box * 0.32, box * 0.22), Vector2(-0.5, 1.0), w * 2.0, ink)
		AffordanceRules.VERB_TAKE:
			# Something small lifted upwards.
			draw_circle(c + Vector2(0.0, box * 0.26), box * 0.16, ink)
			draw_circle(c + Vector2(0.0, box * 0.26), box * 0.16 - w * 0.8, Palette.CREAM)
			draw_line(c + Vector2(0.0, box * 0.04), c + Vector2(0.0, -box * 0.34), ink, w, true)
			_arrow_head(c + Vector2(0.0, -box * 0.40), Vector2(0.0, -1.0), w * 2.6, ink)
		AffordanceRules.VERB_PLACE:
			# Down onto a surface.
			draw_line(c + Vector2(0.0, -box * 0.36), c + Vector2(0.0, box * 0.06), ink, w, true)
			_arrow_head(c + Vector2(0.0, box * 0.16), Vector2(0.0, 1.0), w * 2.6, ink)
			draw_line(c + Vector2(-box * 0.34, box * 0.32), c + Vector2(box * 0.34, box * 0.32), ink, w * 1.2, true)
		AffordanceRules.VERB_ENTER:
			# An arched doorway with an arrow going in.
			var top: Vector2 = c + Vector2(0.0, -box * 0.12)
			draw_arc(top, box * 0.30, PI, TAU, 18, ink, w, true)
			draw_line(top + Vector2(-box * 0.30, 0.0), top + Vector2(-box * 0.30, box * 0.44), ink, w, true)
			draw_line(top + Vector2(box * 0.30, 0.0), top + Vector2(box * 0.30, box * 0.44), ink, w, true)
			draw_line(c + Vector2(-box * 0.44, box * 0.10), c + Vector2(box * 0.02, box * 0.10), ink, w, true)
			_arrow_head(c + Vector2(box * 0.10, box * 0.10), Vector2(1.0, 0.0), w * 2.4, ink)
		AffordanceRules.VERB_HUG:
			_heart(c + Vector2(0.0, -box * 0.02), box * 0.30, ink)
			_heart(c + Vector2(0.0, -box * 0.02), box * 0.30 - w * 0.9, Palette.CREAM)
		AffordanceRules.VERB_CARRY:
			# A box held up in two arms.
			var carried: Rect2 = Rect2(c + Vector2(-box * 0.24, -box * 0.30), Vector2(box * 0.48, box * 0.36))
			draw_rect(carried, ink, true)
			draw_rect(carried.grow(-w * 0.9), Palette.CREAM, true)
			draw_arc(c + Vector2(0.0, box * 0.02), box * 0.34, PI * 0.15, PI * 0.85, 16, ink, w, true)
			draw_circle(c + Vector2(-box * 0.30, box * 0.30), w * 0.9, ink)
			draw_circle(c + Vector2(box * 0.30, box * 0.30), w * 0.9, ink)
		AffordanceRules.VERB_FEED:
			# Bunny's bottle: a capsule with a teat.
			draw_line(c + Vector2(0.0, -box * 0.08), c + Vector2(0.0, box * 0.30), ink, box * 0.34, true)
			draw_line(c + Vector2(0.0, -box * 0.08), c + Vector2(0.0, box * 0.30), Palette.CREAM, box * 0.34 - w * 1.8, true)
			draw_circle(c + Vector2(0.0, -box * 0.28), box * 0.11, ink)
			draw_line(c + Vector2(-box * 0.10, box * 0.08), c + Vector2(box * 0.10, box * 0.08), ink, w * 0.7, true)
			draw_line(c + Vector2(-box * 0.10, box * 0.20), c + Vector2(box * 0.10, box * 0.20), ink, w * 0.7, true)
		_:
			draw_circle(c, box * 0.16, ink)


func _arrow_head(tip: Vector2, direction: Vector2, half: float, color: Color) -> void:
	var d: Vector2 = direction.normalized()
	var side: Vector2 = Vector2(-d.y, d.x)
	var base: Vector2 = tip - d * half * 1.5
	draw_colored_polygon(PackedVector2Array([tip, base + side * half, base - side * half]), color)


func _heart(c: Vector2, r: float, color: Color) -> void:
	draw_circle(c + Vector2(-r * 0.5, -r * 0.25), r * 0.55, color)
	draw_circle(c + Vector2(r * 0.5, -r * 0.25), r * 0.55, color)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 1.02, -r * 0.05), c + Vector2(r * 1.02, -r * 0.05), c + Vector2(0.0, r * 0.95),
	]), color)
