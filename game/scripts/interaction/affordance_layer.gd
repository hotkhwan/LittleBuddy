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
## The PICTURE is small -- a disc 12.8 % of the screen's height, 96 px on an
## iPad, so it never hides the thing it points at -- and the TAP TARGET is not:
## the invisible hit box under it stays at least 240 px whatever the viewport.
## A press on that box that turns out to have nothing to do is handed to the
## floor router, so no tap ever dies under a badge.
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
## Every drawn size below is stated at the REFERENCE height and scaled by
## `badge_scale()` -- the disc is 12.8 % of the viewport's height whatever the
## device: 96 px on a 1334x750 iPad frame, 138 px at 2340x1080. The first build
## drew a 148 px disc at every size, and on the iPad it hid the thing it was
## pointing at (owner feedback, 2026-09-20).
const REFERENCE_HEIGHT: float = 750.0
const BADGE_DIAMETER_FRACTION: float = 0.128
const BADGE_RADIUS: float = 48.0
const OUTLINE_PX: float = 4.0
const MIN_SCALE: float = 0.7
const MAX_SCALE: float = 2.2
## How far above the object's highlight ring the badge floats.
const BADGE_LIFT: float = 40.0
const EDGE_MARGIN: float = 22.0
## The top band nothing may sit in unless the HUD says otherwise: the star
## counter and the Home button live there. `set_top_keep_out()` raises it while
## a prompt is on screen.
const TOP_MARGIN: float = 40.0
## Gap between the highlight ring and a badge placed beside it.
const SIDE_GAP: float = 28.0
## Breathing room around every keep-out rect (the stick, Home, Next ...).
const KEEP_OUT_PAD: float = 6.0
## How far a badge may slide off its preferred spot to clear a keep-out before
## it stops being "beside the object" and becomes a badge for nothing.
const MAX_SLIDE_PX: float = 260.0
## The care close-up's node name. While it is visible the room is not being
## played and no badge may show, whoever mounted this layer.
const CARE_OVERLAY_NAME: String = "CareOverlay"

## The word under the picture: 22 px at the reference height, on a cream pill
## that fits the word (SOON's pill carries a short sentence).
const LABEL_FONT_SIZE: int = 22
const LABEL_WIDTH: float = 104.0
const LABEL_HEIGHT: float = 30.0
const LABEL_GAP: float = 8.0
const LABEL_PAD: float = 16.0

## The highlight ring around the thing itself, px, clamped so a fridge across
## the room and a table under the camera both get a ring you can see.
const RING_MIN_PX: float = 36.0
const RING_MAX_PX: float = 150.0
const RING_WIDTH: float = 5.0
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
## Screen rects the badge must never cover, by name: the HUD pushes its Home,
## Next, Speak, stars and version rects; the thumbstick's zone is read live
## from the world's joystick. See `place_badge()`.
var _keep_outs: Dictionary = {}
## Where the badge ended up relative to the ring: "above", "left", "right"
## or "below".
var _placement: String = "above"
## Instance ids of targets this layer has already given its context provider.
var _provided: Dictionary = {}

var _current: Dictionary = {}
var _shown_key: String = ""
## The projected speech bubble of a character target, viewport px, or an empty
## rect. A transient keep-out: it moves with him and only matters while the
## badge is his.
var _bubble_rect: Rect2 = Rect2()
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


## A screen rect the badge must stay out of. An empty rect removes the entry.
func set_keep_out(key: String, rect: Rect2) -> void:
	build()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_keep_outs.erase(key)
	else:
		_keep_outs[key] = rect


func clear_keep_outs() -> void:
	build()
	_keep_outs.clear()


## Every keep-out in force right now: the pushed rects plus the thumbstick's
## live activation zone.
func get_keep_out_rects() -> Array:
	var rects: Array = _keep_outs.values()
	var stick: Rect2 = _joystick_rect()
	if stick.size.x > 0.0 and stick.size.y > 0.0:
		rects.append(stick)
	return rects


func _joystick_rect() -> Rect2:
	if _world == null or not is_instance_valid(_world) or not _world.has_method("get_joystick"):
		return Rect2()
	var stick: Variant = _world.call("get_joystick")
	if not (stick is Object) or not is_instance_valid(stick) or not stick.has_method("get_activation_rect"):
		return Rect2()
	return stick.call("get_activation_rect")


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


## -- Sizing --------------------------------------------------------------------

## How much bigger (or smaller) than the reference every drawn size is, for a
## viewport `view_height` px tall. Pure, so a test can pin 96 px on the iPad.
static func badge_scale(view_height: float) -> float:
	if view_height <= 0.0:
		return 1.0
	return clampf(view_height * BADGE_DIAMETER_FRACTION / (BADGE_RADIUS * 2.0), MIN_SCALE, MAX_SCALE)


## The disc's drawn diameter at `view_height`, px.
static func badge_diameter(view_height: float) -> float:
	return BADGE_RADIUS * 2.0 * badge_scale(view_height)


## The pill's width for `verb`'s label at `scale`: the reference width, or wider
## when the words need it.
static func label_width_for(verb: String, scale: float, font: Font = null) -> float:
	var text: String = AffordanceRules.label_for(verb)
	var measured: float = 0.0
	var f: Font = font if font != null else ThemeDB.fallback_font
	if f != null:
		measured = f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1,
				int(round(LABEL_FONT_SIZE * scale))).x + LABEL_PAD * scale
	return maxf(LABEL_WIDTH * scale, measured)


## The live scale for this layer's viewport.
func current_scale() -> float:
	var view: Vector2 = _view_size()
	return badge_scale(view.y)


func _view_size() -> Vector2:
	var view: Vector2 = Vector2.ZERO
	if is_inside_tree():
		view = get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		view = size
	if view.x <= 0.0 or view.y <= 0.0:
		view = Vector2(1334.0, REFERENCE_HEIGHT)
	return view


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
	if is_care_overlay_visible():
		return {}
	var here: Vector3 = SpatialUtil.world_position(_actor)
	var facing: Vector3 = -SpatialUtil.world_transform(_actor).basis.z
	return AffordanceRules.pick(_candidates(), here, _preferred_now(), facing)


## True while a `CareOverlay` beside this layer is showing. Checked here as
## well as through the HUD's `set_enabled()`, because the world may mount this
## layer itself and a close-up must silence it whoever built it.
func is_care_overlay_visible() -> bool:
	var host: Node = get_parent()
	if host == null:
		return false
	var care: Node = host.get_node_or_null(CARE_OVERLAY_NAME)
	return care is CanvasItem and (care as CanvasItem).visible


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
		# Providers may spell the verb any way they like; the badge speaks in
		# one voice. A word with no picture is dropped here, loudly in debug.
		var verb: String = AffordanceRules.normalize_verb(entry.get("verb", ""))
		if verb.is_empty():
			push_warning("AffordanceLayer: %s offered unknown verb '%s'; ignored."
					% [str(candidate), str(entry.get("verb", ""))])
			continue
		entry["verb"] = verb
		if not entry.has("targetId"):
			if candidate.has_method("get_activity_target_id"):
				entry["targetId"] = String(candidate.call("get_activity_target_id"))
			elif candidate.has_method("get_activity_target"):
				# Bunny: the provider is the actor, the semantic id lives on the
				# target he carries, and the mission names THAT id.
				var carried: Variant = candidate.call("get_activity_target")
				if carried is Object and is_instance_valid(carried) \
						and carried.has_method("get_activity_target_id"):
					entry["targetId"] = String(carried.call("get_activity_target_id"))
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

	context["carrying"] = carrying_kind(_actor)

	if target.has_method("is_door") and bool(target.call("is_door")):
		var destination: Dictionary = {}
		if target.has_method("get_destination"):
			destination = target.call("get_destination")
		var to_room: String = String(destination.get("toRoomId", ""))
		context["door"] = {"locked": not to_room.is_empty() and not is_room_open(to_room)}
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

	# A character's target (Bunny's `child_actor.gd` builds one) must never
	# read TAKE off its `pickUp` action: the words for a person are HUG, CARRY
	# and FEED. Detected off the actor API rather than a name, so a second
	# child works the same. Carrying is Agent C's call and stays off here.
	var owner_node: Node = (target as Node).get_parent() if target is Node else null
	if owner_node != null and owner_node.has_method("satisfy") and owner_node.has_method("attend"):
		var actions: Array = []
		if target.has_method("get_supported_actions"):
			actions = target.call("get_supported_actions")
		var feedable: bool = false
		var held_item: String = String(context.get("held", ""))
		if not AffordanceRules.is_nothing(held_item):
			var rules_path: String = "res://scripts/kitchen/kitchen_rules.gd"
			if ResourceLoader.exists(rules_path):
				var rules: GDScript = load(rules_path)
				feedable = rules != null and bool(rules.is_feedable(held_item))
		context["character"] = {
			"canHug": actions.has("comfort") or actions.has("hug"),
			"canCarry": false,
			"canFeed": feedable,
		}
		return context

	if not context.has("station") and _world.has_method("get_current_room"):
		var room: Variant = _world.call("get_current_room")
		if room is Object and is_instance_valid(room):
			if room.has_method("get_storage") and room.call("get_storage", local_id) != null:
				var is_open: bool = false
				if room.has_method("is_storage_open"):
					is_open = bool(room.call("is_storage_open", local_id))
				var can_place: bool = true
				if String(context["carrying"]) == "item" and room.has_method("can_store_node"):
					can_place = bool(room.call("can_store_node", local_id, _carried_node(_actor)))
				context["storage"] = {"isOpen": is_open, "canPlace": can_place}
			elif room.has_method("is_openable") and bool(room.call("is_openable", local_id)):
				# The wardrobe: doors on hinges, no shelf model behind them. OPEN
				# is still the word, and it says the same thing shut or open.
				var doors_open: bool = bool(room.call("is_open", local_id))
				context["storage"] = {"isOpen": doors_open, "canPlace": false}
	return context


## `"child"` while a child actor rides in `actor`'s arms, `"item"` for any other
## carried node, `""` for empty arms. Duck-typed off the carry API.
static func carrying_kind(actor: Object) -> String:
	var carried: Object = _carried_node(actor)
	if carried == null:
		return ""
	return "child" if carried.has_method("set_carried_by") else "item"


static func _carried_node(actor: Object) -> Node:
	if actor == null or not is_instance_valid(actor) or not actor.has_method("get_carried_node"):
		return null
	var carried: Variant = actor.call("get_carried_node")
	if carried is Node and is_instance_valid(carried):
		return carried
	return null


## -- Locked rooms ---------------------------------------------------------------
##
## Free Play keeps some rooms for later. The layer does not know why; it is
## handed a gate -- `func(room_id: String) -> bool`, true when the room may be
## entered -- and a door to a room the gate refuses shows SOON instead of ENTER.
## No gate means every room is open, which is Story's world exactly as it was.
var _room_gate: Callable = Callable()


func set_room_gate(gate: Callable) -> void:
	build()
	_room_gate = gate


func is_room_open(room_id: String) -> bool:
	if not _room_gate.is_valid():
		return true
	return bool(_room_gate.call(room_id))


func _station_context(station_id: String, described: Dictionary, held: String) -> Dictionary:
	var opens: bool = false
	var can_place: bool = false
	var can_cook: bool = false
	var rules_path: String = "res://scripts/kitchen/kitchen_rules.gd"
	if ResourceLoader.exists(rules_path):
		var rules: GDScript = load(rules_path)
		if rules != null:
			opens = bool(rules.opens(station_id))
			var resting: String = String(described.get("on", AffordanceRules.NONE))
			if AffordanceRules.is_nothing(resting):
				resting = AffordanceRules.NONE
			if not AffordanceRules.is_nothing(held):
				can_cook = not AffordanceRules.is_nothing(rules.combination(station_id, resting, held))
				can_place = bool(rules.can_place(station_id, held, resting)) or can_cook
	return {
		"opens": opens,
		"isOpen": bool(described.get("open", false)),
		"inside": described.get("inside", []),
		"on": String(described.get("on", AffordanceRules.NONE)),
		"canPlace": can_place,
		"canCook": can_cook,
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

	var view: Vector2 = _view_size()
	var scale: float = badge_scale(view.y)
	_ring_px = clampf(_ring_px, RING_MIN_PX * scale, RING_MAX_PX * scale)
	var target: Variant = _current.get("target", null)
	var character: bool = is_character_target(target)
	var keep_outs: Array = get_keep_out_rects()
	_bubble_rect = _bubble_keep_out(camera, target) if character else Rect2()
	if _bubble_rect.size.x > 0.0:
		keep_outs.append(_bubble_rect)
	var verb: String = String(_current.get("verb", ""))
	var placed: Dictionary = place_badge(
		_screen, _ring_px, view, _top_keep_out, _actor_screen_x(camera), keep_outs, character,
		label_width_for(verb, scale, _font))
	_badge = placed["centre"]
	_placement = String(placed["placement"])
	# The hit box never shrinks with the picture: 240 px stays the floor, and a
	# badge drawn bigger than that gets a box that covers the whole of it.
	var footprint: Rect2 = badge_footprint(_badge, scale, label_width_for(verb, scale, _font))
	var hit_size: Vector2 = Vector2(
		maxf(HIT_SIZE, footprint.size.x), maxf(HIT_SIZE, footprint.size.y + BADGE_RADIUS * scale))
	_hit.size = hit_size
	_hit.position = _badge - hit_size * 0.5
	_hit.visible = true
	_laid_out = true


## True for a person: the provider (or the target's owner) has a speech bubble.
static func is_character_target(target: Variant) -> bool:
	return _bubble_owner(target) != null


static func _bubble_owner(target: Variant) -> Object:
	if not (target is Object) or not is_instance_valid(target):
		return null
	if target.has_method("get_need_bubble"):
		return target
	if target is Node:
		var parent: Node = (target as Node).get_parent()
		if parent != null and parent.has_method("get_need_bubble"):
			return parent
	return null


## The character's speech bubble on screen -- the backing panel's four corners
## projected and boxed -- or an empty rect when there is none to avoid. His
## line ("I'm hungry, Aliz!") is the one thing a badge about HIM must never
## cover; the first build put HUG squarely on it.
func _bubble_keep_out(camera: Camera3D, target: Variant) -> Rect2:
	var owner_node: Object = _bubble_owner(target)
	if owner_node == null or camera == null:
		return Rect2()
	if owner_node.has_method("is_bubble_suppressed") and bool(owner_node.call("is_bubble_suppressed")):
		return Rect2()
	var bubble: Variant = owner_node.call("get_need_bubble")
	if not (bubble is Node3D) or not is_instance_valid(bubble) or not (bubble as Node3D).visible:
		return Rect2()
	var half: Vector2 = Vector2(0.42, 0.055)
	if owner_node.has_method("get_bubble_backing_half_extents"):
		half = owner_node.call("get_bubble_backing_half_extents")
	half = Vector2(maxf(half.x, 0.05), maxf(half.y, 0.03))
	var centre: Vector3 = SpatialUtil.world_position(bubble as Node3D)
	var basis: Basis = SpatialUtil.world_transform(camera).basis
	var rect: Rect2 = Rect2()
	var first: bool = true
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner: Vector3 = centre + basis.x * (half.x * sx) + basis.y * (half.y * sy)
			if camera.is_position_behind(corner):
				return Rect2()
			var point: Vector2 = camera.unproject_position(corner)
			if first:
				rect = Rect2(point, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(point)
	return rect.grow(8.0)


## The bubble rect the last layout kept out of, for a harness to assert against.
func get_bubble_keep_out() -> Rect2:
	return _bubble_rect


## The badge's on-screen footprint -- disc, outline and the word pill -- for a
## badge centred at `centre` at `scale` (1.0 is the 750 px reference). What the
## keep-outs are tested against.
static func badge_footprint(centre: Vector2, scale: float = 1.0, label_width: float = -1.0) -> Rect2:
	var half: float = (BADGE_RADIUS + OUTLINE_PX) * scale
	var pill: float = label_width if label_width > 0.0 else LABEL_WIDTH * scale
	var width: float = maxf(half * 2.0, pill)
	return Rect2(
		Vector2(centre.x - width * 0.5, centre.y - half),
		Vector2(width, half + (BADGE_RADIUS + LABEL_GAP + LABEL_HEIGHT) * scale)
	)


## What the keep-outs are measured against: the drawn footprint AND the
## invisible hit box under it, whichever reaches further. The picture got small
## and the hit box did not, so a badge whose picture clears the stick could
## still have its press box over it; the box is what the thumb meets.
static func placement_rect(centre: Vector2, scale: float = 1.0, label_width: float = -1.0) -> Rect2:
	var footprint: Rect2 = badge_footprint(centre, scale, label_width)
	var hit: Rect2 = Rect2(centre - Vector2(HIT_SIZE, HIT_SIZE) * 0.5, Vector2(HIT_SIZE, HIT_SIZE))
	return footprint.merge(hit)


## Where the badge goes. Pure, so `test_affordance.gd` can prove every rule
## without a camera.
##
##   `screen`       -- the object's anchor, viewport px
##   `ring_px`      -- the highlight ring's radius
##   `view`         -- viewport size
##   `top_keep_out` -- nothing above this line (the HUD's prompt band)
##   `actor_x`      -- Aliz's screen x, so a side placement steps AWAY from her
##   `keep_outs`    -- rects the badge may not cover: the stick, Home, Next ...
##   `prefer_beside` -- a character: his bubble lives above his head, so the
##                     order becomes beside, other side, below, and above last
##
## Order of preference: above the ring; beside it on the side away from Aliz;
## beside it on the other side; below it. The first spot that fits the screen
## and covers no keep-out wins. When every spot covers something, the one that
## covers least does -- a badge the child can still see beats none at all.
## Returns `{"centre": Vector2, "placement": String}`.
static func place_badge(screen: Vector2, ring_px: float, view: Vector2, top_keep_out: float,
		actor_x: float, keep_outs: Array, prefer_beside: bool = false,
		label_width: float = -1.0) -> Dictionary:
	var s: float = badge_scale(view.y)
	var radius: float = BADGE_RADIUS * s
	var pill_w: float = label_width if label_width > 0.0 else LABEL_WIDTH * s
	var min_x: float = EDGE_MARGIN + maxf(radius + OUTLINE_PX * s, pill_w * 0.5)
	var max_x: float = maxf(min_x, view.x - min_x)
	var min_y: float = maxf(top_keep_out, TOP_MARGIN) + radius
	var max_y: float = maxf(min_y, view.y - (EDGE_MARGIN + radius + (LABEL_GAP + LABEL_HEIGHT) * s))

	# The side away from Aliz, and failing a clear answer, away from the
	# nearer screen edge -- which is also the side with room on it.
	var away_from_edge: float = -1.0 if screen.x > view.x * 0.5 else 1.0
	var away_from_actor: float = away_from_edge
	if actor_x > screen.x + 8.0:
		away_from_actor = -1.0
	elif actor_x < screen.x - 8.0:
		away_from_actor = 1.0
	var side_offset: float = ring_px + SIDE_GAP * s + radius
	var vertical_offset: float = ring_px + BADGE_LIFT * s + radius

	var above: Dictionary = {"placement": "above", "centre": screen + Vector2(0.0, -vertical_offset)}
	var near_side: Dictionary = {"placement": "left" if away_from_actor < 0.0 else "right",
			"centre": screen + Vector2(away_from_actor * side_offset, -radius * 0.4)}
	var far_side: Dictionary = {"placement": "left" if away_from_actor > 0.0 else "right",
			"centre": screen + Vector2(-away_from_actor * side_offset, -radius * 0.4)}
	var below: Dictionary = {"placement": "below",
			"centre": screen + Vector2(0.0, vertical_offset + LABEL_HEIGHT * s)}
	var candidates: Array = [near_side, far_side, below, above] if prefer_beside \
			else [above, near_side, far_side, below]

	# Pass 0: every spot exactly where it wants to be. Pass 1: each spot slid
	# outward along its own direction until it clears whatever it landed on --
	# a toy box in the stick's corner gets its badge just past the stick's
	# edge, still beside the box. Unslid always beats slid: a badge 260 px
	# above its object is worse than one beside it that needed no slide. And
	# among the slid spots the SHORTEST slide wins, not the first in the list:
	# 17 px further right beats 135 px further up.
	var best: Dictionary = {}
	var best_overlap: float = INF
	for pass_index: int in range(2):
		var shortest: Dictionary = {}
		var shortest_slide: float = INF
		for candidate: Dictionary in candidates:
			var wanted: Vector2 = candidate["centre"]
			var placement: String = String(candidate["placement"])
			# "Above" only counts when it really is above: clamped down onto the
			# object it would sit on whatever stands in front of it.
			if placement == "above" and wanted.y < min_y:
				continue
			var centre: Vector2 = Vector2(clampf(wanted.x, min_x, max_x), clampf(wanted.y, min_y, max_y))
			var measured: Dictionary = _overlap(placement_rect(centre, s, pill_w), keep_outs)
			var slide: float = 0.0
			if pass_index == 1:
				if float(measured["overlap"]) <= 0.0:
					continue
				var slid: Vector2 = _slid_clear(placement, centre, placement_rect(centre, s, pill_w), measured["block"])
				slid = Vector2(clampf(slid.x, min_x, max_x), clampf(slid.y, min_y, max_y))
				slide = slid.distance_to(centre)
				if slide > MAX_SLIDE_PX * s or slid.is_equal_approx(centre):
					continue
				centre = slid
				measured = _overlap(placement_rect(centre, s, pill_w), keep_outs)
			var overlap: float = float(measured["overlap"])
			if overlap <= 0.0:
				if pass_index == 0:
					return {"centre": centre, "placement": placement}
				if slide < shortest_slide:
					shortest_slide = slide
					shortest = {"centre": centre, "placement": placement}
				continue
			if overlap < best_overlap:
				best_overlap = overlap
				best = {"centre": centre, "placement": placement}
		if not shortest.is_empty():
			return shortest
	if best.is_empty():
		# Every candidate was ruled out before overlap was even measured (an
		# absurdly tall keep-out); fall back to the first side, clamped.
		var side: Dictionary = candidates[1]
		var wanted: Vector2 = side["centre"]
		best = {"centre": Vector2(clampf(wanted.x, min_x, max_x), clampf(wanted.y, min_y, max_y)),
				"placement": String(side["placement"])}
	return best


## Total area of `footprint` inside any keep-out, and the first rect it hit.
static func _overlap(footprint: Rect2, keep_outs: Array) -> Dictionary:
	var overlap: float = 0.0
	var first_block: Rect2 = Rect2()
	for entry: Variant in keep_outs:
		if not (entry is Rect2):
			continue
		var blocked: Rect2 = (entry as Rect2).grow(KEEP_OUT_PAD)
		if footprint.intersects(blocked):
			var hit: Rect2 = footprint.intersection(blocked)
			overlap += hit.size.x * hit.size.y
			if first_block.size == Vector2.ZERO:
				first_block = blocked
	return {"overlap": overlap, "block": first_block}


## The centre that puts `footprint` just past `blocked`, moving only along the
## candidate's own direction (a side badge slides sideways, a top badge up).
static func _slid_clear(placement: String, centre: Vector2, footprint: Rect2, blocked: Rect2) -> Vector2:
	match placement:
		"right":
			return Vector2(centre.x + (blocked.end.x - footprint.position.x) + 1.0, centre.y)
		"left":
			return Vector2(centre.x - (footprint.end.x - blocked.position.x) - 1.0, centre.y)
		"above":
			return Vector2(centre.x, centre.y - (footprint.end.y - blocked.position.y) - 1.0)
		_:
			return Vector2(centre.x, centre.y + (blocked.end.y - footprint.position.y) + 1.0)


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
	if not perform():
		# Nothing to do here after all (the hands are full, the target has no
		# id). The child pressed the floor under the badge, and the floor must
		# answer exactly as if the badge were not there: the hit box is a STOP
		# control, so the press is handed to the router by hand.
		_route_press_to_floor(event)
	accept_event()


func _route_press_to_floor(event: InputEvent) -> void:
	if _nav == null or not is_instance_valid(_nav) or not _nav.has_method("handle_tap"):
		return
	var at: Vector2 = Vector2.ZERO
	if event is InputEventMouse:
		at = (event as InputEventMouse).global_position
	elif event is InputEventScreenTouch:
		at = (event as InputEventScreenTouch).position
	else:
		return
	_nav.call("handle_tap", at)


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
		if not routed and _actor != null and is_instance_valid(_actor) \
				and _actor.has_method("get_current_target_id") \
				and String(_actor.call("get_current_target_id")) == target_id:
			# Already walking there: the second tap changed nothing, and that is
			# the anti-jitter rule working, not a dead press.
			routed = true
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
	var s: float = current_scale()
	var outline: float = OUTLINE_PX * s
	var ring_w: float = RING_WIDTH * s

	# The thing itself: a ring in the verb's colour, breathing at the art
	# bible's 0.6 Hz, with a faint cream halo so it reads on any wall.
	draw_arc(_screen, _ring_px + (8.0 + pulse * 5.0) * s, 0.0, TAU, 56,
			Color(Palette.CREAM.r, Palette.CREAM.g, Palette.CREAM.b, 0.16 + pulse * 0.12), ring_w + 4.0 * s, true)
	draw_arc(_screen, _ring_px + pulse * 4.0 * s, 0.0, TAU, 56,
			Color(tint.r, tint.g, tint.b, 0.62 + pulse * 0.28), ring_w, true)
	draw_arc(_screen, _ring_px + pulse * 4.0 * s, 0.0, TAU, 56,
			Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.22), 1.5 * s, true)

	# The badge bobs gently so it reads as alive, and squashes on a press.
	var bob: float = sin(_clock * TAU * 0.9) * 3.0 * s
	var squash: float = 1.0
	if _press_clock >= 0.0:
		var t: float = clampf(_press_clock / PRESS_SEC, 0.0, 1.0)
		squash = 1.0 - 0.12 * sin(t * PI)
	var centre: Vector2 = _badge + Vector2(0.0, bob)
	var radius: float = BADGE_RADIUS * s * squash

	# Pointer tail towards the object, drawn first so the disc sits on it.
	var towards: Vector2 = Vector2(0.0, 1.0)
	if _placement == "left":
		towards = Vector2(1.0, 0.0)
	elif _placement == "right":
		towards = Vector2(-1.0, 0.0)
	elif _placement == "below":
		towards = Vector2(0.0, -1.0)
	var across: Vector2 = Vector2(-towards.y, towards.x)
	var tail_tip: Vector2 = centre + towards * (radius + 14.0 * s)
	var tail: PackedVector2Array = PackedVector2Array([
		centre + towards * (radius - 8.0 * s) - across * 13.0 * s,
		centre + towards * (radius - 8.0 * s) + across * 13.0 * s, tail_tip,
	])
	var tail_outline: PackedVector2Array = PackedVector2Array([
		centre + towards * (radius - 9.0 * s) - across * 17.0 * s,
		centre + towards * (radius - 9.0 * s) + across * 17.0 * s,
		tail_tip + towards * 4.5 * s,
	])
	draw_colored_polygon(tail_outline, Palette.INK)
	draw_colored_polygon(tail, tint)

	# A soft drop shadow under the disc, the way the asset sheet's badges sit
	# proud of the screen; then ink, cream and the coloured face.
	draw_circle(centre + Vector2(0.0, 3.0 * s), radius + outline,
			Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.18))
	draw_circle(centre, radius + outline, Palette.INK)
	draw_circle(centre, radius + outline - 2.0 * s, Palette.CREAM)
	draw_circle(centre, radius, tint)
	# A soft highlight on the upper left, the way every prop in the house has one.
	draw_circle(centre + Vector2(-radius * 0.34, -radius * 0.38), radius * 0.22,
			Color(Palette.CREAM.r, Palette.CREAM.g, Palette.CREAM.b, 0.55))

	_draw_glyph(verb, centre, radius * 1.18)

	# The word, on a cream pill under the disc.
	var pill_w: float = label_width_for(verb, s, _font)
	var pill_h: float = LABEL_HEIGHT * s
	var pill: Rect2 = Rect2(
		Vector2(centre.x - pill_w * 0.5, centre.y + radius + LABEL_GAP * s),
		Vector2(pill_w, pill_h)
	)
	_pill.set_corner_radius_all(int(pill_h * 0.5))
	_pill.set_border_width_all(maxi(2, int(round(2.5 * s))))
	draw_style_box(_pill, pill)
	if _font != null:
		var font_size: int = int(round(LABEL_FONT_SIZE * s))
		var baseline: float = pill.position.y + pill_h * 0.5 \
				+ _font.get_ascent(font_size) * 0.5 - 2.0 * s
		draw_string(_font, Vector2(pill.position.x, baseline), AffordanceRules.label_for(verb),
				HORIZONTAL_ALIGNMENT_CENTER, pill_w, font_size, Palette.INK)


## One picture per word, all ink strokes on the coloured disc. `box` is the
## square the picture fills; every shape is rounded or a simple arrow.
func _draw_glyph(verb: String, c: Vector2, box: float) -> void:
	var w: float = maxf(box * 0.085, 3.0)
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
			# Down onto a pad: the same oval the drop zones draw on the floor.
			_oval(c + Vector2(0.0, box * 0.30), box * 0.36, box * 0.13, ink)
			_oval(c + Vector2(0.0, box * 0.30), box * 0.36 - w * 0.9, box * 0.13 - w * 0.6, Palette.CREAM)
			draw_line(c + Vector2(0.0, -box * 0.40), c + Vector2(0.0, -box * 0.02), ink, w, true)
			_arrow_head(c + Vector2(0.0, box * 0.10), Vector2(0.0, 1.0), w * 2.6, ink)
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
			# A small child -- round head, rounded body -- cradled in two arms.
			var head: Vector2 = c + Vector2(0.0, -box * 0.24)
			draw_circle(head, box * 0.15, ink)
			draw_circle(head, box * 0.15 - w * 0.8, Palette.CREAM)
			var body: Rect2 = Rect2(c + Vector2(-box * 0.17, -box * 0.08), Vector2(box * 0.34, box * 0.28))
			draw_rect(body, ink, true)
			draw_rect(body.grow(-w * 0.8), Palette.CREAM, true)
			# The arms: two curves coming up under the body and around it.
			draw_arc(c + Vector2(0.0, box * 0.02), box * 0.36, PI * 0.12, PI * 0.88, 18, ink, w * 1.1, true)
			draw_line(c + Vector2(-box * 0.35, box * 0.14), c + Vector2(-box * 0.43, -box * 0.14), ink, w * 1.1, true)
			draw_line(c + Vector2(box * 0.35, box * 0.14), c + Vector2(box * 0.43, -box * 0.14), ink, w * 1.1, true)
			draw_circle(c + Vector2(-box * 0.43, -box * 0.14), w * 0.8, ink)
			draw_circle(c + Vector2(box * 0.43, -box * 0.14), w * 0.8, ink)
		AffordanceRules.VERB_FEED:
			# Bunny's bottle: a capsule with a teat.
			draw_line(c + Vector2(0.0, -box * 0.08), c + Vector2(0.0, box * 0.30), ink, box * 0.34, true)
			draw_line(c + Vector2(0.0, -box * 0.08), c + Vector2(0.0, box * 0.30), Palette.CREAM, box * 0.34 - w * 1.8, true)
			draw_circle(c + Vector2(0.0, -box * 0.28), box * 0.11, ink)
			draw_line(c + Vector2(-box * 0.10, box * 0.08), c + Vector2(box * 0.10, box * 0.08), ink, w * 0.7, true)
			draw_line(c + Vector2(-box * 0.10, box * 0.20), c + Vector2(box * 0.10, box * 0.20), ink, w * 0.7, true)
		AffordanceRules.VERB_SIT:
			# An armchair seen from the front: a back, a seat and two arms.
			var back: Rect2 = Rect2(c + Vector2(-box * 0.24, -box * 0.38), Vector2(box * 0.48, box * 0.40))
			draw_rect(back, ink, true)
			draw_rect(back.grow(-w * 0.8), Palette.CREAM, true)
			var seat: Rect2 = Rect2(c + Vector2(-box * 0.36, -box * 0.02), Vector2(box * 0.72, box * 0.24))
			draw_rect(seat, ink, true)
			draw_rect(seat.grow(-w * 0.8), Palette.CREAM, true)
			for side: float in [-1.0, 1.0]:
				draw_line(c + Vector2(side * box * 0.28, box * 0.22), c + Vector2(side * box * 0.28, box * 0.40), ink, w * 1.2, true)
		AffordanceRules.VERB_WASH:
			# A tap with a bend, and three drops falling from it.
			draw_line(c + Vector2(-box * 0.30, -box * 0.02), c + Vector2(-box * 0.30, -box * 0.30), ink, w * 1.3, true)
			draw_line(c + Vector2(-box * 0.30, -box * 0.30), c + Vector2(box * 0.10, -box * 0.30), ink, w * 1.3, true)
			draw_line(c + Vector2(box * 0.10, -box * 0.30), c + Vector2(box * 0.10, -box * 0.14), ink, w * 1.3, true)
			draw_line(c + Vector2(-box * 0.40, -box * 0.02), c + Vector2(-box * 0.20, -box * 0.02), ink, w * 1.1, true)
			for drop: Array in [[0.10, 0.02, 1.0], [-0.02, 0.22, 0.8], [0.20, 0.26, 0.7]]:
				var at: Vector2 = c + Vector2(box * float(drop[0]), box * float(drop[1]))
				var r: float = w * 1.3 * float(drop[2])
				draw_circle(at + Vector2(0.0, r * 0.5), r, ink)
				draw_colored_polygon(PackedVector2Array([
					at + Vector2(-r * 0.9, r * 0.4), at + Vector2(r * 0.9, r * 0.4), at + Vector2(0.0, -r * 1.4),
				]), ink)
		AffordanceRules.VERB_COOK:
			# A round bowl with a spoon standing in it, and two curls of steam.
			_oval(c + Vector2(0.0, box * 0.12), box * 0.36, box * 0.12, ink)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-box * 0.36, box * 0.12), c + Vector2(box * 0.36, box * 0.12),
				c + Vector2(box * 0.22, box * 0.40), c + Vector2(-box * 0.22, box * 0.40),
			]), ink)
			_oval(c + Vector2(0.0, box * 0.12), box * 0.36 - w * 0.9, box * 0.12 - w * 0.6, Palette.CREAM)
			draw_line(c + Vector2(box * 0.10, box * 0.10), c + Vector2(box * 0.30, -box * 0.30), ink, w, true)
			draw_circle(c + Vector2(box * 0.32, -box * 0.33), w * 1.1, ink)
			for x: float in [-0.14, 0.06]:
				draw_arc(c + Vector2(box * x, -box * 0.22), box * 0.07, PI * 0.5, PI * 1.5, 8, ink, w * 0.8, true)
				draw_arc(c + Vector2(box * x, -box * 0.36), box * 0.07, -PI * 0.5, PI * 0.5, 8, ink, w * 0.8, true)
		AffordanceRules.VERB_SOON:
			# A little signpost with a star on it: not now, and nothing is wrong.
			draw_line(c + Vector2(0.0, box * 0.10), c + Vector2(0.0, box * 0.42), ink, w * 1.2, true)
			var sign: Rect2 = Rect2(c + Vector2(-box * 0.34, -box * 0.34), Vector2(box * 0.68, box * 0.44))
			draw_rect(sign, ink, true)
			draw_rect(sign.grow(-w * 0.8), Palette.CREAM, true)
			_star(c + Vector2(0.0, -box * 0.12), box * 0.16, Palette.STAR_EARNED, ink, w * 0.6)
		_:
			draw_circle(c, box * 0.16, ink)


func _star(centre: Vector2, r: float, fill: Color, rim: Color, rim_w: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(10):
		var angle: float = -PI * 0.5 + TAU * float(index) / 10.0
		var radius: float = r if index % 2 == 0 else r * 0.45
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, fill)
	var closed: PackedVector2Array = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, rim, rim_w, true)


func _oval(centre: Vector2, half_w: float, half_h: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(28):
		var angle: float = TAU * float(index) / 28.0
		points.append(centre + Vector2(cos(angle) * half_w, sin(angle) * half_h))
	draw_colored_polygon(points, color)


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
