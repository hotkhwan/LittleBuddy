extends Node3D

## ============================================================================
## LITTLE BUDDY, IN THE HOUSE -- the child as an inhabitant, not a prop.
## ============================================================================
##
## The thing the caregiver looks after. It owns the child's stats, decides what
## the child needs, shows the matching pose, and says so.
##
## ## Why this exists on top of the wrapper
##
## `baby_little_buddy.gd` knows how to SHOW a pose and nothing else -- by design,
## so a re-export changes one file. `child_needs.gd` knows what is TRUE and
## nothing else. Neither should own a `BabyState` or a speech bubble, so this is
## the node that joins them and is the only thing `house_world` has to find.
##
## ## ...and it makes him move
##
## Added 2026-09-19. `child_life.gd` decides what Bunny's body should be doing --
## breathing, fussing, being fed, pleased -- and this node plays it on the rigged
## model's real `AnimationPlayer`. See the "Bunny is alive" section below, which
## is also where the one piece of procedural motion in the pass is named as one.
##
## ## Urgency, the face and the blink (added 2026-09-20)
##
## A need that goes unanswered for `child_life.gd::IGNORED_AFTER_SEC` while
## Bunny is standing about ESCALATES, all three channels together: the bubble
## switches to the need's louder line (`child_needs.gd::LINES_URGENT`), the
## face goes to `hmph` (brows in, puffed cheeks), and every `STAMP_EVERY_SEC`
## the body plays the one-shot `stamp` clip and returns to fussing. The clock
## is `_ignored_for`, kept here because only this node knows the activity, the
## carry and the happy window; the decisions are `child_life.gd`'s. It resets
## the moment the need changes, the child is picked up, cared for or fed. It is
## a request getting louder, not a timer running out: nothing is lost.
##
## The blink is a `set_eyes_closed()` on the wrapper for `BLINK_CLOSED_SEC`
## every `BLINK_GAP_MIN_SEC`..`BLINK_GAP_MAX_SEC`, clocked in `live()` (this
## node already runs a frame loop; the wrapper must not). Skipped while the
## mood itself has the eyes shut.
##
## Public, all safe without the rigged model:
##   `get_ignored_for() -> float`, `is_urgent() -> bool`
##   `set_blinking(enabled)`, `is_blinking_enabled() -> bool`, `blink_now()`
##   `get_line()` now returns the urgent line while `is_urgent()`.
##
## ## The bubble is the whole point
##
## A child whose need is invisible is furniture. The floating line is how a
## player who cannot read a stat bar -- which is every player, there is no stat
## bar -- knows that Little Buddy is hungry and that going to the kitchen is the
## thing to do. It is `Label3D` so it is lit, occluded and scaled by the same
## camera as the child, and sits in the room rather than on top of it.

const WrapperScript := preload("res://scripts/characters/little_buddy/baby_little_buddy.gd")
## The voice pack (2026-09-20): Bunny SAYS his need when it changes ("I'm
## hungry, Aliz!", "I'm sleepy.") and gives one "Hmph!" when a need has been
## left long enough to escalate. Cue calls only, null-guarded: without the
## `Voice` autoload the bubble is all there is, as before.
const VoiceBridge := preload("res://scripts/voice/voice_bridge.gd")
const VoiceCues := preload("res://scripts/voice/voice_cues.gd")
const StatsScript := preload("res://scripts/care/child_stats.gd")
const Needs := preload("res://scripts/care/child_needs.gd")
const Present := preload("res://scripts/care/child_presentation.gd")
const Palette := preload("res://scripts/ui/palette.gd")
const Follower := preload("res://scripts/care/child_follower.gd")
const Life := preload("res://scripts/care/child_life.gd")
const ActivityTargetScript := preload("res://scripts/navigation/activity_target.gd")
const InteractionPointScript := preload("res://scripts/navigation/interaction_point.gd")
const SpatialUtil := preload("res://scripts/navigation/spatial_util.gd")
const AffordanceRulesScript := preload("res://scripts/interaction/affordance_rules.gd")

## Emitted when the child's dominant need changes, so a mission can react without
## polling. Empty string means content.
signal need_changed(need: String)
## Emitted when the visible pose changes, so a test can assert the cut happened.
signal activity_changed(activity: String, pose: String)
## Emitted once when the child finishes walking to where it was sent.
signal arrived()
## Emitted when the clip Bunny's body is playing changes, so a test can assert
## that a hungry child actually fusses rather than only being described as one.
signal life_changed(clip: String)

## Clear of the CAREGIVER, not just the child.
##
## Raising it was the first attempt and it is not enough. Aliz stands BEHIND a
## 0.78 m child and is more than twice his height, so every height that clears
## his head lands somewhere on her -- the bubble simply moved from her hair to
## her chest, which is where the close-up camera now frames it. Height alone
## cannot solve an overlap in depth.
##
## So the bubble also steps SIDEWAYS, away from whichever side she is on -- but
## only while she is actually in the way. See `_place_bubble()`, which is where
## the two things the first version of this got wrong are written down.
const BUBBLE_HEIGHT: float = 1.02

## Half of Aliz's silhouette, in metres, hair included.
##
## Measured off the verification shots rather than chosen: at the close-up the
## beat composes she renders ~0.54 m wide including hair, and her arms swing a
## little wider than that. `docs/BUBBLE_VERIFICATION.md` has the frames.
const CAREGIVER_HALF_WIDTH: float = 0.30
## Daylight left between the line and her, once neither is overlapping. Small
## enough that the bubble stays near the child it belongs to, large enough that
## "clear of her" survives a step of her walk cycle.
const BUBBLE_CLEAR_MARGIN: float = 0.12
## Used when the rendered width cannot be measured -- no text yet, or a build
## whose text server has not shaped the line. It is the width of the longest need
## line (`"I need changing."`) halved, so the fallback errs wide.
const BUBBLE_FALLBACK_HALF_WIDTH: float = 0.42
## Inside this, "which side is she on" has no answer worth acting on, so the last
## answer is kept. Without it the bubble would jump across him the instant she
## crossed his centre line -- and standing dead behind him is exactly what the
## beat makes her do.
const BUBBLE_SIDE_DEADZONE: float = 0.12
const BUBBLE_FONT_SIZE: int = 56
const BUBBLE_PIXEL_SIZE: float = 0.0016

## -- The bubble's backing --------------------------------------------------------
##
## Added 2026-09-20. The line was ink text with a cream outline and nothing
## behind it, and over a cream wall -- which is most of the house -- the outline
## and the wall are the same colour, so the outline did nothing and the line
## read as loose brown letters on beige (`docs/shots/aliz_after_house.png`). It
## now sits on a rounded cream panel with a dusty-blue rim, a soft warm shadow,
## and a small tail pointing at Bunny's head: a speech bubble, which is what it
## always was meant to read as. `docs/BUBBLE_BACKING_PASS.md` has the frames.
##
## The panel is ONE unlit quad, a child of the label, drawn by the small SDF
## shader at the bottom of this file. See `_build_bubble_backing()` for why a
## shader rather than a texture, and for the render-order decisions.

## Cream around the shaped text, in metres: sideways, and above/below.
const BUBBLE_PAD := Vector2(0.06, 0.04)
const BUBBLE_CORNER_RADIUS: float = 0.07
## The rim's thickness. ~3 px at the close-up on an iPad, ~1.5 px in a wide room
## shot -- thin, but the shader anti-aliases it so it never drops out.
const BUBBLE_RIM: float = 0.011
## High but not opaque: a sliver of the room shows through, which is what keeps
## the panel reading as a bubble IN the room rather than a sticker on the glass.
const BUBBLE_FILL_ALPHA: float = 0.94
## A soft warm shadow, offset down-right. Warm `ink`, never black (ART_BIBLE §3).
const BUBBLE_SHADOW_OFFSET := Vector2(0.008, -0.014)
const BUBBLE_SHADOW_ALPHA: float = 0.22
const BUBBLE_SHADOW_SOFT: float = 0.022
## The tail: a wedge on the bottom edge whose apex leans towards Bunny's head, so
## when the line has stepped 0.7 m sideways to clear Aliz it still visibly
## belongs to him. Short on purpose -- it must never reach his face.
const BUBBLE_TAIL_LENGTH: float = 0.065
const BUBBLE_TAIL_HALF_BASE: float = 0.038
## Where the tail aims: the top of a 0.78 m child's head, a little below the
## crown so the aim survives his idle bob. `shots_bubble.gd` uses the same figure.
const CHILD_HEAD_HEIGHT: float = 0.72
## Used when the font cannot be measured. Half the height of a 56 px line at
## `BUBBLE_PIXEL_SIZE`, so the fallback is the common case rather than a guess.
const BUBBLE_FALLBACK_HALF_HEIGHT: float = 0.055
## Transparent geometry sorts by `render_priority` FIRST and by depth second, and
## the panel and the glyphs sit at exactly the same depth (same origin, both
## billboarded about it), so the order is decided here and nowhere else:
## backing, then the glyph outline, then the glyphs. The `Label3D` defaults are
## 0 for the text and -1 for the outline; both are raised ABOVE the backing rather
## than the backing pushed below -1, so the bubble as a whole still sorts by depth
## against everything else that is transparent in the room (tap ripples, drop
## zones) instead of always losing to it.
const BUBBLE_BACKING_RENDER_PRIORITY: int = 0
const BUBBLE_OUTLINE_RENDER_PRIORITY: int = 1
const BUBBLE_TEXT_RENDER_PRIORITY: int = 2

var _state: RefCounted = null
var _wrapper: Node3D = null
var _bubble: Label3D = null
var _backing: MeshInstance3D = null
var _backing_quad: QuadMesh = null
var _backing_material: ShaderMaterial = null
## Half extents of the panel (text + pad, no tail, no shadow) in metres.
var _backing_half: Vector2 = Vector2.ZERO
## The text the panel was last sized for. A carriage return can never be a need
## line, so it is the "never fitted" sentinel; "" is a real (content) line.
var _backing_fitted_text: String = "\r"
## While true the line and its backing are hidden whatever the need is. See
## `set_bubble_suppressed()`.
var _bubble_suppressed: bool = false
## When each need was last SAID (msec), so a stat hovering around its threshold
## cannot make him chatter: one line per need per `NEED_LINE_COOLDOWN_SEC`.
var _need_said_msec: Dictionary = {}
## The one "Hmph!" per ignored need.
var _urgent_voiced: bool = false
const NEED_LINE_COOLDOWN_SEC: float = 20.0
var _activity: String = Present.ACTIVITY_IDLE
## Which act the activity is, when the caller knows. See `set_activity()`.
var _activity_detail: String = ""
var _need: String = ""
var _built: bool = false

## -- Bubble placement ----------------------------------------------------------
## Which side of Bunny the line steps towards: -1 screen-left, +1 screen-right.
## Remembered rather than recomputed, so that while the caregiver is standing
## dead behind him -- which is where the beat puts her -- the line stays on the
## side it was already on instead of having to invent one.
var _bubble_side: float = -1.0

## -- Being carried -----------------------------------------------------------------
## The caregiver holding him, or null. While set, this node's transform belongs to
## her `carry_controller.gd`; the follower, the attention turn and his tap target
## all stand down. See `set_carried_by()`.
var _carrier: Node3D = null

## -- Accompaniment -------------------------------------------------------------
var _follow_state: String = Follower.STATE_WAITING
var _following: Node3D = null
var _attend_point: Vector3 = Vector3.ZERO
var _attending: bool = false
var _player: AnimationPlayer = null

## -- Life ----------------------------------------------------------------------
##
## See `child_life.gd` for the decisions; these are only what has to be
## remembered between frames to apply them.
var _life_clip: String = ""
var _walking: bool = false
var _happy_left: float = 0.0
## Degrees, on the MODEL rather than on this node -- see `_attend_to_caregiver()`.
var _model_yaw: float = 0.0
var _watching: bool = false
var _caregiver: Node3D = null
var _looked_for_caregiver: bool = false

## -- Urgency and the blink ------------------------------------------------------
## Seconds the current uncomfortable need has waited while nothing was being
## done about it; the escalation clock. See the class doc.
var _ignored_for: float = 0.0
## The `_ignored_for` value the last stamp played at; negative for none yet.
var _last_stamp_at: float = -1.0
## Set for exactly one `_apply_life()` when a stamp is due.
var _stamp_pending: bool = false
var _urgent: bool = false
## Seconds until the next blink begins, then seconds until it ends.
var _blink_in: float = 4.0
var _blink_left: float = 0.0
var _blink_enabled: bool = true
var _blink_rng := RandomNumberGenerator.new()

## The blink: shut for this long, every so often, randomised.
const BLINK_CLOSED_SEC: float = 0.12
const BLINK_GAP_MIN_SEC: float = 3.0
const BLINK_GAP_MAX_SEC: float = 6.0


func _ready() -> void:
	# DEFERRED, and the deferral is a shipping-path fix rather than a style choice.
	#
	# `build()` ends up asking for the caregiver, which walks up to `HouseWorld`
	# and calls `get_character()` -- a LAZY getter that begins `build_world()`.
	# Run straight from `_ready()`, that started assembling the world while the
	# bedroom node was still setting up its own children. Godot refuses
	# `add_child()` in that state, so `room.gd` had BOTH of its calls rejected,
	# marked itself built, and left its Geometry parented to nothing: THE BEDROOM
	# RENDERED AS AN EMPTY CREAM VOID with the characters floating in it.
	#
	# One frame later the tree has settled and every lookup answers properly.
	# Nothing waits on this: `build()` is idempotent and every public method
	# calls it first, so anything that arrives sooner builds the actor itself.
	build.call_deferred()


## `build()` can legitimately run OUTSIDE the tree: `get_activity_target()`
## reaches it while `house_world.place_in_room()` is still assembling the room,
## and the actor may not be parented at all yet.
##
## `_find_caregiver()` LATCHES its miss -- one failed walk up the ancestry and it
## answers null for the rest of the session, by design, so a bare Bunny does not
## re-search every frame. Those two together mean an actor built a moment too
## early would never find Aliz again: no attention turn, and a need bubble that
## never dodges anybody. Entering the tree is the first moment the ancestry is
## real, so the miss is retired and the line re-placed.
func _notification(what: int) -> void:
	if what != NOTIFICATION_ENTER_TREE or not _built:
		return
	if _caregiver == null:
		_looked_for_caregiver = false
	_place_bubble()


## Idempotent and callable before `_ready()`, for the same reason every other
## wrapper in this project is: the headless runner never fires `_ready()` for a
## node added to the root.
func build() -> void:
	if _built:
		return
	_built = true
	_state = StatsScript.new()
	_blink_rng.randomize()
	_blink_in = _blink_rng.randf_range(BLINK_GAP_MIN_SEC, BLINK_GAP_MAX_SEC)
	# The affordance contract: anything in this group answers `get_affordance()`
	# and `perform_affordance()`, and the HUD draws the verb it returns.
	add_to_group(AFFORDABLE_GROUP)

	_wrapper = WrapperScript.new()
	_wrapper.name = "Model"
	add_child(_wrapper)
	_wrapper.call("build")

	_bubble = Label3D.new()
	_bubble.name = "NeedBubble"
	_bubble.font_size = BUBBLE_FONT_SIZE
	_bubble.pixel_size = BUBBLE_PIXEL_SIZE
	_bubble.modulate = Palette.INK
	_bubble.outline_size = 14
	_bubble.outline_modulate = Palette.CREAM
	# Billboarded: the child is small and may be approached from any side, and a
	# line the player has to walk around to read is not a signal.
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.render_priority = BUBBLE_TEXT_RENDER_PRIORITY
	_bubble.outline_render_priority = BUBBLE_OUTLINE_RENDER_PRIORITY
	add_child(_bubble)
	_build_bubble_backing()
	# Over his own head, which is where it belongs when there is nobody to dodge.
	# `_refresh()` below, and `live()` every frame after that, move it aside only
	# if the caregiver turns out to be in the way.
	_apply_bubble_offset(Vector3.ZERO)

	# A pose cut is also a RIG cut: only the rigged export has a skeleton, so the
	# player that drives Bunny's body belongs to whichever pose is on screen.
	# Caching it once was a live bug -- the wrapper starts on the rigged model,
	# the first `_refresh()` used to cut to the seated export, and every clip
	# afterwards played on a model that had been hidden one line earlier.
	if _wrapper.has_signal("pose_changed"):
		_wrapper.connect("pose_changed", _on_pose_changed)
	_resolve_player()
	_build_target()
	_refresh()


func _on_pose_changed(_pose_name: String) -> void:
	_resolve_player()
	_life_clip = ""
	_apply_life()


## The `AnimationPlayer` of the pose currently VISIBLE, asked of the wrapper
## rather than searched for: a subtree search finds whichever player it meets
## first, which with two poses loaded is as likely to be the hidden one.
##
## Null is a correct answer, not a failure -- it is what a pose-locked export
## honestly has -- and `_apply_life()` plays nothing when it gets one.
func _resolve_player() -> void:
	if _wrapper != null and _wrapper.has_method("get_animation_player"):
		_player = _wrapper.call("get_animation_player") as AnimationPlayer
		return
	_player = _find_player(_wrapper)


## The child is a place Buddy can WALK TO.
##
## Without this the caregiver can see Little Buddy and never reach him, and the
## first mission step ("go and talk to the child") has no target to name. So the
## child registers its own `ActivityTarget`, rather than the room having to know
## that a child might be standing in it.
##
## Node order matters and is not cosmetic: `ActivityTarget._ensure_resolved()`
## latches on its first call and caches whatever `InteractionPoint` exists at
## that moment, so the shape and the marker are added BEFORE any property is set.
## `room.gd::_add_target()` documents the same trap, and getting it wrong puts
## the stand position inside a wall.
const TARGET_SUFFIX: String = "littleBuddy"
## Where Buddy stands to talk to the child: in front of it, an arm's length away.
const STAND_OFFSET := Vector3(0.0, 0.0, 0.62)

var _target: Area3D = null


func _build_target() -> void:
	_target = Area3D.new()
	_target.name = TARGET_SUFFIX
	_target.set_script(ActivityTargetScript)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	# Generous: a four-year-old taps a region, and the child is only 0.78 m tall.
	box.size = Vector3(0.66, 0.9, 0.66)
	shape.shape = box
	shape.position = Vector3(0.0, 0.45, 0.0)
	_target.add_child(shape)

	var point := Marker3D.new()
	point.name = "InteractionPoint"
	point.set_script(InteractionPointScript)
	point.position = STAND_OFFSET
	_target.add_child(point)

	# LOCAL id only. `ActivityTarget` prefixes `room_id` itself to build the
	# semantic id, so passing "bedroom.littleBuddy" here yields
	# "bedroom.bedroom.littleBuddy" -- which is what the first version did.
	var room_id: String = _room_id_of(self)
	_target.set("target_id", TARGET_SUFFIX)
	_target.set("display_name", "Little Buddy")
	_target.set("arrival_radius", 0.3)
	if "room_id" in _target:
		_target.set("room_id", room_id)
	if _target.has_method("set_supported_actions"):
		_target.call("set_supported_actions", ["talkTo", "comfort", "pickUp"])
	add_child(_target)


func get_activity_target() -> Area3D:
	build()
	return _target


func _room_id_of(node: Node) -> String:
	var walker: Node = node.get_parent()
	while walker != null:
		if walker.has_method("get_room_id"):
			return String(walker.call("get_room_id"))
		walker = walker.get_parent()
	return ""


## -- Accompaniment ---------------------------------------------------------------

## Start walking after `buddy`. Passing null stops.
##
## Following, not carrying: the rigged child has real walk and run clips, so this
## is honest. Carrying would need a hold pose on Buddy and an attach point on her
## rig, and she has neither -- so it is not faked.
func follow(buddy: Node3D) -> void:
	build()
	_following = buddy
	_attending = false
	if buddy == null and _follow_state != Follower.STATE_ATTENDING:
		_follow_state = Follower.STATE_WAITING
		_play_clip("")


## Stand at a fixed world point and face it -- a sink, a bed. Wins over
## following, so a child placed for a care act stays put while Buddy shuffles.
func attend(world_point: Vector3) -> void:
	build()
	_attend_point = world_point
	_attending = true
	_follow_state = Follower.STATE_ATTENDING
	global_position = Vector3(world_point.x, global_position.y, world_point.z)
	_play_clip("")


func stop_attending() -> void:
	_attending = false
	_follow_state = Follower.STATE_WAITING


func get_follow_state() -> String:
	return _follow_state


## Advances the walk. Split out of `_process` so a headless smoke test drives
## exactly the same code a device does.
func step(delta: float) -> void:
	# Carried: the follower stands down entirely. His transform is hers.
	if not _built or _carrier != null or _attending or _following == null:
		return
	var target: Vector3 = Follower.follow_point(
		_following.global_position, -_following.global_transform.basis.z)

	# Stranded: only ever resolved while a transition covers the screen, so the
	# child never pops in front of the camera. `room_changed()` is that moment.
	var previous: String = _follow_state
	_follow_state = Follower.next_state(
		previous, global_position, target, true, false)

	_walking = _follow_state == Follower.STATE_FOLLOWING
	if _walking:
		global_position = Follower.step_towards(global_position, target, delta)
		var facing: Vector3 = Follower.facing_for(_follow_state, global_position, target)
		if facing.length_squared() > 0.0001:
			# The model faces -Z, so look along the travel direction.
			look_at(global_position - facing, Vector3.UP)
		# Walking beats looking at anybody: a child cannot watch Aliz over its
		# shoulder and walk after her at the same time without reading as broken.
		_model_yaw = 0.0
		_watching = false

	if _follow_state == Follower.STATE_ARRIVING and previous != Follower.STATE_ARRIVING:
		arrived.emit()


func _process(delta: float) -> void:
	step(delta)
	live(delta)


## Called by the world when Buddy changes room. The child is MOVED, not walked:
## walking it through a wall is worse than a cut, and the transition fade is
## already covering the screen -- which is the only moment a re-place is allowed.
func room_changed(new_room: Node3D, buddy: Node3D) -> void:
	build()
	if new_room != null and get_parent() != new_room:
		var keep: Transform3D = SpatialUtil.world_transform(self)
		if get_parent() != null:
			get_parent().remove_child(self)
		new_room.add_child(self)
		SpatialUtil.set_world_position(self, keep.origin)
		if is_inside_tree():
			global_transform = keep
	# In her arms he stays in her arms: the carry controller re-pins him to her
	# socket on its next step, so no follow point is wanted here.
	if _carrier != null:
		return
	if buddy != null:
		global_position = Follower.follow_point(
			buddy.global_position, -buddy.global_transform.basis.z)
	_follow_state = Follower.STATE_WAITING
	_play_clip("")


## -- Bunny is alive --------------------------------------------------------------
##
## The brief for this pass was one sentence: "Bunny must not remain a rigid
## statue." He was one, and for a concrete reason -- the rigged export ships with
## `walk`, `run` and nothing else, so the instant he stopped walking there was
## nothing to play and he froze in his bind pose in the middle of the bedroom
## while a mission about his hunger ran around him.
##
## What is here now:
##
##   * **an idle** -- breathing, a weight shift, and a slow look around the room;
##   * **a fuss** whose PACE is driven by the real `ChildStats.hunger` axis, so
##     the same motion reads as more urgent the hungrier he actually is;
##   * **attention** -- he turns to watch Aliz when she comes near, and turns
##     back when she leaves;
##   * **feeding** -- a spoon or a bottle, chosen by which need is loudest;
##   * **being pleased** for a few seconds after he is cared for.
##
## All five are `AnimationPlayer` clips on the model's real skeleton, authored in
## `baby_life_clips.gd`. **The one thing here that is not a clip** is the
## attention turn: that is a plain yaw on the model node, stepped per frame by
## `child_life.gd::turn_towards()`. It is procedural, it is called procedural,
## and it is a body turn rather than a limb motion precisely because a body turn
## is the one thing a rotation can honestly express.

## Advances everything that is alive about Bunny. Split out of `_process()` for
## the same reason `step()` is: a headless test drives exactly the code a device
## does, one frame at a time.
func live(delta: float) -> void:
	if not _built:
		return
	if _happy_left > 0.0:
		_happy_left = maxf(_happy_left - delta, 0.0)
		if _happy_left == 0.0:
			_apply_life()
	_tick_ignored(delta)
	_tick_blink(delta)
	_attend_to_caregiver(delta)
	# The bubble dodges the CAREGIVER, and she walks. Re-placing it only when the
	# child refreshed -- which is what the first version did -- meant the side was
	# picked once at `build()` and then never again, so it never actually dodged
	# anything. It is a dot product and a basis multiply, and only while the line
	# is on screen at all.
	if _bubble != null and _bubble.visible:
		_place_bubble()
	# One-shot clips (`eat`, `drink`) end by themselves; re-applying picks the
	# next spoonful up, or drops back to the idle, without a signal round trip.
	if _player != null and not _player.is_playing():
		_apply_life()


## -- Being ignored ------------------------------------------------------------------

## Advances the escalation clock while a need is being left alone; resets it
## the moment anything is being done about the child.
func _tick_ignored(delta: float) -> void:
	var waiting: bool = _carrier == null and _activity == Present.ACTIVITY_IDLE \
			and _happy_left <= 0.0 and Life.is_uncomfortable_need(_need)
	if not waiting:
		if _ignored_for > 0.0 or _urgent:
			_reset_ignored()
			_refresh()
		return
	_ignored_for += delta
	if not _urgent and Life.is_ignored(_ignored_for):
		# Escalate: the line, the face and the body, in one refresh.
		_urgent = true
		_refresh()
		_say_urgent()
	if not _walking and _player != null and Life.stamp_due(_ignored_for, _last_stamp_at):
		_last_stamp_at = _ignored_for
		_stamp_pending = true
		_apply_life()


func _reset_ignored() -> void:
	_ignored_for = 0.0
	_last_stamp_at = -1.0
	_stamp_pending = false
	_urgent = false
	_urgent_voiced = false


## -- Voice cues -----------------------------------------------------------------

## Bunny says the need he just got, at most once per need per cooldown. Never
## interrupts anyone (a Bunny line queues behind Aliz by the pack's rules).
func _say_need(need: String) -> void:
	if need.is_empty() or _bubble_suppressed:
		return
	var line_id: String = VoiceCues.for_need(need)
	if line_id.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var last: int = int(_need_said_msec.get(need, -1_000_000))
	if now - last < int(NEED_LINE_COOLDOWN_SEC * 1000.0):
		return
	if VoiceBridge.say_lines(self, [line_id]):
		_need_said_msec[need] = now


## One "Hmph!" when a need has waited long enough to escalate; the face already
## went to the `hmph` through `child_life.gd`. Once per wait.
func _say_urgent() -> void:
	if _urgent_voiced or _bubble_suppressed:
		return
	if VoiceBridge.cue(self, VoiceCues.EVENT_NEED_URGENT):
		_urgent_voiced = true


## Test hooks for the cooldown.
func get_need_line_cooldown_sec() -> float:
	return NEED_LINE_COOLDOWN_SEC


func has_voiced_urgent() -> bool:
	return _urgent_voiced


## -- The blink ------------------------------------------------------------------------

func _tick_blink(delta: float) -> void:
	if not _blink_enabled or _wrapper == null or not _wrapper.has_method("set_eyes_closed"):
		return
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			_blink_left = 0.0
			_wrapper.call("set_eyes_closed", false)
			_blink_in = _blink_rng.randf_range(BLINK_GAP_MIN_SEC, BLINK_GAP_MAX_SEC)
		return
	_blink_in -= delta
	if _blink_in > 0.0:
		return
	_blink_in = _blink_rng.randf_range(BLINK_GAP_MIN_SEC, BLINK_GAP_MAX_SEC)
	if bool(_wrapper.call("are_eyes_closed")):
		return   # the mood already has them shut; nothing to blink
	if bool(_wrapper.call("set_eyes_closed", true)):
		_blink_left = BLINK_CLOSED_SEC


## Switches the blink on or off. Off also reopens the eyes if one was mid-way.
func set_blinking(enabled: bool) -> void:
	build()
	_blink_enabled = enabled
	if not enabled and _blink_left > 0.0:
		_blink_left = 0.0
		if _wrapper != null and _wrapper.has_method("set_eyes_closed"):
			_wrapper.call("set_eyes_closed", false)


func is_blinking_enabled() -> bool:
	return _blink_enabled


## Shuts the eyes now for one blink's length (the next `live()` reopens them).
## For tests and for the shot harness.
func blink_now() -> void:
	build()
	if _wrapper == null or not _wrapper.has_method("set_eyes_closed"):
		return
	if bool(_wrapper.call("set_eyes_closed", true)):
		_blink_left = BLINK_CLOSED_SEC


## -- Where the need bubble goes --------------------------------------------------
##
## Steps the line to the side Aliz is NOT on, so a sentence about Bunny never
## reads as coming out of her chest.
##
## ## The two things the first version got wrong, both now photographed
##
## `docs/BUBBLE_VERIFICATION.md` has the before pictures. Neither was a tuning
## problem; both were the rule being applied in the wrong place.
##
##   1. **World in, LOCAL out.** It compared the caregiver's WORLD x against
##      Bunny's, then wrote the answer into `_bubble.position`, which is the
##      child's LOCAL frame. In the bedroom Bunny is authored yawed 180 degrees,
##      so local +x IS world -x and the sign came out backwards: told she was on
##      his left, the bubble moved onto her.
##      `docs/shots/bubble_BEFORE_left_ipad.png` is the line sitting squarely on
##      her dress.
##   2. **Never re-evaluated.** It ran only from `_refresh()` -- a need change, an
##      activity change -- and Aliz walking over is none of those. So the side was
##      decided once, at `build()`, against wherever she happened to be spawned,
##      and then never moved again for the rest of the session. The five
##      `bubble_BEFORE_*` shots are five different stagings with the line in the
##      identical spot, to the centimetre.
##
## So: the side is chosen along the CAMERA's horizontal axis (which is what
## "beside her on screen" actually means), the result is converted into this
## node's own frame before it is written, and `live()` re-runs it every frame
## while the bubble is up.
##
## ## It steps exactly as far as it has to, and no further
##
## Stepping aside by a FIXED amount was the other half of the bad picture: with
## Aliz already a stride to one side, a bubble shoved the other way lands over
## bare floor with the child nowhere near it, and a line that far from anybody
## belongs to nobody. So the rule is stated as the thing actually wanted --
## `_side_clearance()` metres between the line's centre and hers -- and the step
## is whatever is left over:
##
##     step = max(0, clearance - |how far to the side she already is|)
##
## which is continuous. She walks in from the side and the line slides off his
## head only as she closes; she stands directly behind him and it is at full
## stretch; she wanders away and it settles back over his own head with no
## threshold to flicker across. `docs/shots/bubble_abeam_*.png` is the far end of
## that and `docs/shots/bubble_front_*.png` the near one.
##
## `clearance` is measured, not fixed, because the need lines are not all one
## width: "I'm hungry!" renders ~0.54 m wide and "I need changing." ~0.76 m, and a
## step that clears the short one leaves the long one lying across her.
## `docs/shots/bubble_longline_*.png` is that case.
func _place_bubble() -> void:
	if _bubble == null:
		return
	var right: Vector3 = _screen_right()
	var lateral: Variant = _caregiver_lateral(right)
	if lateral == null:
		# Nobody to dodge, which is a normal answer: Bunny is instantiated bare in
		# several tests, and over his own head is where the line belongs then.
		_apply_bubble_offset(Vector3.ZERO)
		return

	var offset: float = float(lateral)
	if absf(offset) > BUBBLE_SIDE_DEADZONE:
		_bubble_side = -signf(offset)
	var step: float = maxf(_side_clearance() - absf(offset), 0.0)
	_apply_bubble_offset(right * (_bubble_side * step))


## How much room the line needs beside the caregiver's centre, in metres.
func _side_clearance() -> float:
	return CAREGIVER_HALF_WIDTH + _bubble_half_width() + BUBBLE_CLEAR_MARGIN


## Half the rendered width of the line that is on the bubble right now, in metres.
##
## Shaped by the text server rather than estimated from the character count, so a
## font or a `pixel_size` change cannot silently invalidate a hard-coded number.
##
## NOT `Label3D.get_aabb()`, which was the obvious answer and is wrong here: it
## reports the last mesh the renderer BUILT, and a headless run never builds one.
## It answers zero there, every line measures the same, and the rule quietly
## degrades to a constant in exactly the environment the tests run in --
## `test_bubble_placement.gd` caught that on its first run.
func _bubble_half_width() -> float:
	if _bubble == null or _bubble.text.strip_edges().is_empty():
		return BUBBLE_FALLBACK_HALF_WIDTH
	var font: Font = _bubble.font if _bubble.font != null else ThemeDB.fallback_font
	if font == null:
		return BUBBLE_FALLBACK_HALF_WIDTH
	var shaped: float = font.get_string_size(
		_bubble.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, _bubble.font_size).x
	# The outline is drawn OUTSIDE the glyphs, on both sides.
	var width: float = (shaped + float(_bubble.outline_size) * 2.0) * _bubble.pixel_size
	if not is_finite(width) or width < 0.05:
		return BUBBLE_FALLBACK_HALF_WIDTH
	return width * 0.5


## How far the caregiver is to one side of Bunny ON SCREEN, in metres: negative
## screen-left, positive screen-right. Null when there is nobody to dodge.
##
## Read through `SpatialUtil`, not through `global_position`.
##
## `build()` legitimately runs OUTSIDE the tree -- `get_activity_target()` reaches
## it while `house_world.place_in_room()` is still assembling the room -- and
## `Node3D.global_position` asserts `is_inside_tree()` there, logs an error and
## quietly returns the origin. That both floods the log and answers "she is at
## (0,0,0)", which is a wrong answer rather than no answer. `spatial_util.gd`
## exists for precisely this and accumulates the parent transforms by hand, so the
## side is correct even before the actor is parented.
func _caregiver_lateral(right: Vector3) -> Variant:
	var caregiver: Node3D = _find_caregiver()
	if caregiver == null or not is_instance_valid(caregiver):
		return null
	var to_her: Vector3 = SpatialUtil.world_position(caregiver) - SpatialUtil.world_position(self)
	return to_her.dot(right)


## The world direction that points to the RIGHT of the frame, flattened onto the
## floor.
##
## Asked of whichever camera is rendering rather than assumed to be world +x. It
## happens to be +x today -- every room authors `yaw = 0` -- but "which side of
## the screen is she on" is a question about the camera, and a house that ever
## framed a room from another angle would otherwise silently start putting the
## bubble on the wrong side again. `Vector3.RIGHT` is the same answer at yaw 0,
## so the fallback for "no camera" is not a different rule.
func _screen_right() -> Vector3:
	if not is_inside_tree():
		return Vector3.RIGHT
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera == null or not camera.is_inside_tree():
		return Vector3.RIGHT
	var right: Vector3 = camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return Vector3.RIGHT
	return right.normalized()


## Writes a WORLD-space offset into the bubble's LOCAL position, which is the
## conversion the first version was missing. Yaw-only in practice, so this is an
## exact inverse rather than an approximation.
func _apply_bubble_offset(world_offset: Vector3) -> void:
	if _bubble == null:
		return
	var wanted: Vector3 = world_offset + Vector3(0.0, BUBBLE_HEIGHT, 0.0)
	_bubble.position = SpatialUtil.world_transform(self).basis.inverse() * wanted
	# The backing is a CHILD of the label at its origin, so it has just moved with
	# it. What is left is to size it for the line (only when the line changed) and
	# to point its tail back at the head the line has stepped away from.
	_fit_bubble_backing()
	_aim_bubble_tail(wanted)


## -- The backing panel -----------------------------------------------------------
##
## One `MeshInstance3D` with a `QuadMesh`, parented to the label at its origin,
## drawn by `BACKING_SHADER`.
##
## ## Why a child of the label
##
## The placement rule above writes ONE position, `_bubble.position`, every frame,
## and it has been wrong twice. A sibling that mirrors that position is a second
## copy of the answer that can drift from the first; a child has no position of
## its own to get wrong, and it inherits `visible`, so the panel appears and
## disappears on exactly the line `_refresh()` already throws (`_apply_bubble_
## visibility()`) with no second switch to forget. `Label3D` billboards in its
## material rather than by rotating its node, so the child is NOT billboarded by
## the parent -- the shader does its own, about the same origin, and the two
## therefore always face the camera together.
##
## ## Why a shader rather than a texture
##
## The line's width varies by half again between "I'm hungry!" and "I need
## changing.", and the panel is drawn at anything from ~190 px/m (a wide room) to
## ~600 px/m (the iPhone close-up). A rounded texture stretched to fit smears its
## corners and thins its rim; regenerating one per need change is a per-pixel
## loop in GDScript on the render thread's frame. A signed-distance shader is the
## same quad at every size and every resolution, the rim is a constant metre
## width, and the tail is three more lines of arithmetic. It is unshaded, reads
## no texture, does no lighting, casts no shadow and disables fog -- one alpha-
## blended quad, which is the budget `CLAUDE.md` sets.
##
## ## Depth
##
## The quad is depth-TESTED like the label (neither has `no_depth_test`), and
## like every alpha-blended material it does not write depth. So a wall between
## the camera and the bubble hides both the panel and the text together, rather
## than one showing through where the other does not.
func _build_bubble_backing() -> void:
	_backing_quad = QuadMesh.new()
	_backing_material = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = BACKING_SHADER
	_backing_material.shader = shader
	_backing_material.render_priority = BUBBLE_BACKING_RENDER_PRIORITY
	var fill: Color = Palette.CREAM
	fill.a = BUBBLE_FILL_ALPHA
	var shadow: Color = Palette.INK
	shadow.a = BUBBLE_SHADOW_ALPHA
	_backing_material.set_shader_parameter("fill_color", fill)
	_backing_material.set_shader_parameter("rim_color", Palette.deep(Palette.DUSTY_BLUE))
	_backing_material.set_shader_parameter("shadow_color", shadow)
	_backing_material.set_shader_parameter("shadow_offset", BUBBLE_SHADOW_OFFSET)
	_backing_material.set_shader_parameter("shadow_soft", BUBBLE_SHADOW_SOFT)
	_backing_material.set_shader_parameter("corner_radius", BUBBLE_CORNER_RADIUS)
	_backing_material.set_shader_parameter("rim_width", BUBBLE_RIM)
	_backing_material.set_shader_parameter("tail_half_base", BUBBLE_TAIL_HALF_BASE)

	_backing = MeshInstance3D.new()
	_backing.name = "Backing"
	_backing.mesh = _backing_quad
	_backing.material_override = _backing_material
	_backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backing.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_backing.position = Vector3.ZERO
	_bubble.add_child(_backing)


## Sizes the quad and the panel to the line on the label, once per line.
##
## Width from `_bubble_half_width()` -- the text-server measurement the step
## rule already trusts, never `get_aabb()` -- and height from the font's own
## line height at the label's size. Both are then padded. The QUAD is larger
## than the panel by the tail's reach on every side it can lean towards and by
## the shadow's spread, and is centred a little low so the extra is below,
## where the tail is; the shader leaves that extra transparent.
func _fit_bubble_backing() -> void:
	if _backing == null or _bubble == null:
		return
	if _bubble.text == _backing_fitted_text:
		return
	_backing_fitted_text = _bubble.text
	var half_h: float = BUBBLE_FALLBACK_HALF_HEIGHT
	var font: Font = _bubble.font if _bubble.font != null else ThemeDB.fallback_font
	if font != null:
		var line_height: float = font.get_height(_bubble.font_size) * _bubble.pixel_size
		if is_finite(line_height) and line_height > 0.02:
			half_h = line_height * 0.5
	_backing_half = Vector2(_bubble_half_width(), half_h) + BUBBLE_PAD
	_backing_material.set_shader_parameter("half_size", _backing_half)

	var side_margin: float = BUBBLE_TAIL_LENGTH + BUBBLE_SHADOW_SOFT + absf(BUBBLE_SHADOW_OFFSET.x)
	var above: float = BUBBLE_SHADOW_SOFT
	var below: float = BUBBLE_TAIL_LENGTH + BUBBLE_SHADOW_SOFT + absf(BUBBLE_SHADOW_OFFSET.y)
	_backing_quad.size = Vector2(
		2.0 * (_backing_half.x + side_margin), 2.0 * _backing_half.y + above + below)
	_backing_quad.center_offset = Vector3(0.0, (above - below) * 0.5, 0.0)


## Points the tail at Bunny's head from wherever the panel has ended up.
##
## `bubble_local` is where the panel is relative to Bunny in WORLD metres (the
## offset the step rule chose plus `BUBBLE_HEIGHT`). The head is at
## `CHILD_HEAD_HEIGHT` above his origin, so the vector from panel to head is
## known in world space; it is projected onto the camera's right and up, which
## are the quad's own x and y once billboarded. The tail leaves the bottom edge
## where the line to the head crosses it (clamped clear of the rounded corners)
## and runs `BUBBLE_TAIL_LENGTH` along that line -- never to the head itself.
func _aim_bubble_tail(bubble_local: Vector3) -> void:
	if _backing_material == null or _backing_half == Vector2.ZERO:
		return
	var camera_basis: Basis = _camera_basis()
	var to_head: Vector3 = Vector3(0.0, CHILD_HEAD_HEIGHT, 0.0) - bubble_local
	var tip: Vector2 = Vector2(to_head.dot(camera_basis.x), to_head.dot(camera_basis.y))
	if tip.y > -0.02:
		# The head is level with or above the panel, which the rule never produces
		# in a room; straight down is the honest default for a bare actor.
		tip = Vector2(0.0, -1.0)
	var direction: Vector2 = tip.normalized()
	var bottom: float = -_backing_half.y
	var reach: float = maxf(_backing_half.x - BUBBLE_CORNER_RADIUS - BUBBLE_TAIL_HALF_BASE, 0.0)
	var base_x: float = clampf(tip.x * (bottom / tip.y), -reach, reach)
	# The base sits a rim-width INSIDE the panel so the union with the rounded box
	# has no seam and the rim runs round the wedge rather than across its root.
	_backing_material.set_shader_parameter("tail_base", Vector2(base_x, bottom + BUBBLE_RIM * 2.0))
	_backing_material.set_shader_parameter(
		"tail_tip", Vector2(base_x, bottom) + direction * BUBBLE_TAIL_LENGTH)


## The rendering camera's basis, or identity when there is none -- out of the
## tree, or in the headless runner. Identity makes the tail aim in world x/y,
## which at every room's authored `yaw = 0` is the same answer as the camera's.
func _camera_basis() -> Basis:
	if not is_inside_tree():
		return Basis.IDENTITY
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera == null or not camera.is_inside_tree():
		return Basis.IDENTITY
	return camera.global_transform.basis


## One switch for the line's visibility, so `_refresh()` and
## `set_bubble_suppressed()` cannot disagree about it. The backing is a child of
## the label and follows without being mentioned.
func _apply_bubble_visibility() -> void:
	if _bubble == null:
		return
	_bubble.visible = not _need.is_empty() and not _bubble_suppressed


## Hides the line -- and its backing -- regardless of the need, until told
## otherwise.
##
## For the feeding close-up: the camera is on Bunny, the care overlay's top band
## carries the hint text, and his 3D "I'm hungry!" was showing through the band
## and over-printing it. The director wraps the overlay in this. Un-suppressing
## restores the ordinary rule (`_apply_bubble_visibility()`) at once rather than
## at the next need change, and re-places the line the same frame so it does not
## reappear where it was before the camera moved.
func set_bubble_suppressed(suppressed: bool) -> void:
	build()
	if _bubble_suppressed == suppressed:
		return
	_bubble_suppressed = suppressed
	_apply_bubble_visibility()
	if _bubble != null and _bubble.visible:
		_place_bubble()


func is_bubble_suppressed() -> bool:
	return _bubble_suppressed


## The bubble node, so a test or a screenshot harness can measure the thing on
## screen rather than a number this file agreed with itself about.
func get_need_bubble() -> Label3D:
	build()
	return _bubble


## The panel behind the line: the label's only child.
func get_need_bubble_backing() -> MeshInstance3D:
	build()
	return _backing


## Half the panel's width and height in metres -- text plus padding, without the
## tail or the shadow. What a harness should project to ask "is a face under it".
func get_bubble_backing_half_extents() -> Vector2:
	build()
	return _backing_half


## Where the bubble sits relative to Bunny in WORLD metres -- which is the frame
## the placement rule reasons in, and the frame the bug was in. Positive x is
## world-right, which at every room's authored `yaw = 0` is screen-right.
func get_bubble_world_offset() -> Vector3:
	build()
	if _bubble == null:
		return Vector3.ZERO
	return SpatialUtil.world_transform(self).basis * _bubble.position


## Turns Bunny to watch Aliz, and back again when she goes.
##
## **Rotated: the model, not this node.** Bunny's `ActivityTarget` and its
## `InteractionPoint` are children of this node, and the interaction point is
## where Aliz is told to STAND -- 0.62 m in front of Bunny. Yawing this node
## would swing the place she is walking to around him while she walks to it, and
## the two verified missions both route through that point. The model is a child
## with nothing hanging off it, so turning it turns exactly the thing that should
## turn and nothing that should not.
##
## The per-frame turn is procedural, and is the only procedural motion in this
## pass. It steps an angle towards an angle; it does not sway, bob or breathe.
func _attend_to_caregiver(delta: float) -> void:
	if _wrapper == null or _walking or _attending:
		return
	if _carrier != null:
		# On her chest he faces the way she faces; turning to look at her would
		# put his face in her dress.
		_watching = false
		_model_yaw = Life.turn_towards(_model_yaw, 0.0, delta)
		_wrapper.rotation.y = deg_to_rad(_model_yaw)
		return
	var caregiver: Node3D = _find_caregiver()
	var wanted: float = 0.0
	if caregiver != null:
		# Through `SpatialUtil` for the reason `_caregiver_lateral()` documents:
		# out of the tree `global_position` answers (0, 0, 0) rather than refusing,
		# so Bunny would turn to watch the origin.
		var to_her: Vector3 = SpatialUtil.world_position(caregiver) \
				- SpatialUtil.world_position(self)
		var flat: float = Vector2(to_her.x, to_her.z).length()
		_watching = Life.should_attend(flat, _watching)
		if _watching and flat > 0.01:
			# The model faces -Z at rest, so the yaw that points it at her is the
			# angle of the vector to her measured from -Z. Local, so this node's own
			# rotation is already accounted for.
			var local: Vector3 = SpatialUtil.world_transform(self).basis.inverse() * to_her
			wanted = Life.attend_yaw(rad_to_deg(atan2(-local.x, -local.z)))
	else:
		_watching = false
	_model_yaw = Life.turn_towards(_model_yaw, wanted, delta)
	_wrapper.rotation.y = deg_to_rad(_model_yaw)


## Aliz, found once by asking the world for her rather than by a hard path.
##
## `house_world.gd` exposes `get_character()`; nothing else in the ancestry does,
## so the walk up is unambiguous and this file learns no scene layout. Null is a
## normal answer -- Bunny is instantiated bare in several tests, and a child who
## crashes when nobody is looking after him is worse than one who does not turn.
func _find_caregiver() -> Node3D:
	if _caregiver != null and is_instance_valid(_caregiver):
		return _caregiver
	var walker: Node = get_parent()
	if walker == null:
		# There was nothing to search, so nothing was learned. Latching here is
		# what made an actor built a moment before it was parented -- which
		# `get_activity_target()` really does -- stay caregiver-less for the rest
		# of the session: no attention turn, and a bubble that dodges nobody.
		return null
	if _looked_for_caregiver and _caregiver == null:
		return null
	_looked_for_caregiver = true
	while walker != null:
		if walker.has_method("get_character"):
			var found: Variant = walker.call("get_character")
			_caregiver = found as Node3D
			return _caregiver
		walker = walker.get_parent()
	return null


## Plays whatever `child_life.gd` says Bunny should be doing, at the pace his
## real stats call for.
func _apply_life() -> void:
	if _state == null:
		return
	var stats: Dictionary = _state.call("describe")
	var wanted: String = Life.clip_for(
			stats, _activity, _walking, _happy_left, _activity_detail, _stamp_pending)
	_stamp_pending = false
	# **The face first, and outside every early return below.** It is a texture
	# swap, not a clip, so it is available on a build whose model has no
	# `AnimationPlayer` at all -- and a Bunny who cannot move but can at least
	# look unhappy is strictly better than one who can do neither. Putting it
	# after the `has_animation()` check was the first version, and it meant the
	# face silently stopped following the mood the moment a clip went missing.
	_apply_face(wanted)
	if _player == null:
		return
	if not _player.has_animation(wanted):
		# Honest degradation: a build whose model has no such clip plays nothing
		# rather than substituting a clip that means something else.
		return
	_player.speed_scale = Life.pace_for(wanted, Life.distress(stats), _need)
	if _player.current_animation == wanted and _player.is_playing():
		return
	# Cross-faded rather than cut. Every one of these clips rests every bone it
	# does not animate, so a hard cut between them is a visible snap.
	_player.play(wanted, LIFE_BLEND_SEC)
	if wanted != _life_clip:
		_life_clip = wanted
		life_changed.emit(wanted)


## Seconds of cross-fade between life clips. Short enough that a tap still reads
## as immediate, long enough that fuss -> celebrate is a change of mood rather
## than a jump cut.
const LIFE_BLEND_SEC: float = 0.22


## Repaints the face to match the body.
##
## **This is not facial animation and must not be described as any.** The rigged
## model has no facial bones -- the skeleton ends at `headfront` -- and the eyes
## and mouth are painted into the albedo. `baby_face_moods.gd` redraws those two
## regions of the texture and the wrapper uploads the result. Four variants, no
## interpolation, nothing per frame.
##
## Derived from the CLIP rather than from the need, so the mouth can never
## disagree with the arms: there is one decision, in `child_life.gd`, and both
## halves of the reaction read it.
func _apply_face(clip: String) -> void:
	if _wrapper == null or not _wrapper.has_method("set_face_mood"):
		return
	_wrapper.call("set_face_mood", Life.face_for(clip, _need, _ignored_for))


## The clip Bunny's body is playing, for tests and for the production report.
func get_life_clip() -> String:
	build()
	return _life_clip


## The face currently painted on Bunny -- `content`, `unhappy`, `delighted` or
## `asleep`. `content` is also the honest answer on a build whose texture the
## mood painter did not recognise, because the shipped face IS the content one.
func get_face_mood() -> String:
	build()
	if _wrapper != null and _wrapper.has_method("get_face_mood"):
		return String(_wrapper.call("get_face_mood"))
	return Life.FACE_CONTENT


## How hard Bunny is finding it, 0.0 to 1.0, straight off his real stats.
func get_distress() -> float:
	build()
	return Life.distress(_state.call("describe")) if _state != null else 0.0


## True while Bunny has turned to watch Aliz.
func is_watching_caregiver() -> bool:
	return _watching


func _play_clip(clip: String) -> void:
	if _player == null:
		return
	if clip.is_empty():
		_walking = false
		_apply_life()
		return
	if _player.has_animation(clip) and _player.current_animation != clip:
		_player.play(clip, LIFE_BLEND_SEC)


func _find_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null


## -- Being carried ------------------------------------------------------------------
##
## The signature interaction: Aliz picks Bunny up and carries him. The carrying
## itself -- lifting to the socket, riding it, setting down on a standable spot
## -- is `carry_controller.gd`'s, hung off HER; this node's part is to know it
## is in her arms and to stop doing the things a standing child does.
##
## Nothing about him changes except his transform and his posture. He is not
## re-parented, not duplicated, not hidden: the same node, the same `ChildStats`,
## the same bubble, the same `ActivityTarget` (disabled while held, so a tap on
## him in her arms does not send her walking to a point on her own chest). His
## hunger when he is put down is his hunger when he was picked up.

## The moment the lift begins. `carrier` is the caregiver's body.
func set_carried_by(carrier: Node3D) -> void:
	build()
	_carrier = carrier
	_following = null
	_attending = false
	_walking = false
	_follow_state = Follower.STATE_WAITING
	_watching = false
	if _target != null and _target.has_method("set_target_enabled"):
		_target.call("set_target_enabled", false)
	set_activity(Present.ACTIVITY_CARRIED)


## Back on the floor. Restores everything `set_carried_by()` stood down.
func release_carried() -> void:
	build()
	_carrier = null
	if _target != null and _target.has_method("set_target_enabled"):
		_target.call("set_target_enabled", true)
	if _activity == Present.ACTIVITY_CARRIED:
		set_activity(Present.ACTIVITY_IDLE)


func is_carried() -> bool:
	return _carrier != null


func get_carrier() -> Node3D:
	return _carrier


## -- Affordances ----------------------------------------------------------------------
##
## The data half of the on-screen verb icons. Anything in the `affordable` group
## answers `get_affordance(actor)` with what `actor` could do to it right now --
## or `{}` -- and `perform_affordance(actor)` does it. The HUD owns the icons
## and the tap; this owns the meaning.
##
## For Bunny that is one verb at a time, in this order:
##   * `place` -- he is in this actor's arms: put him down (on a standable spot).
##   * `hug`   -- he needs comfort or is crying: a cuddle answers it.
##   * `carry` -- otherwise: pick him up.
## `radius` is the reach the icon should honour, in metres from his origin; the
## anchor is just above his head so the icon never covers his face.

const AFFORDABLE_GROUP: String = "affordable"
const AFFORD_VERB_CARRY: String = "carry"
const AFFORD_VERB_PLACE: String = "place"
const AFFORD_VERB_HUG: String = "hug"
## An arm's length plus a little: a caregiver standing on his interaction point
## (0.62 m in front of him) is inside it with room for a step of her walk cycle.
const AFFORD_REACH: float = 1.1
const AFFORD_ANCHOR_LIFT: float = 0.16
## Above furniture (1) and a door (1); below nothing, because he IS the game.
const AFFORD_PRIORITY: int = 3


func get_affordance(actor: Node3D) -> Dictionary:
	build()
	if actor == null or not is_instance_valid(actor):
		return {}
	var anchor: Vector3 = SpatialUtil.world_position(self) \
			+ Vector3(0.0, CHILD_HEAD_HEIGHT + AFFORD_ANCHOR_LIFT, 0.0)
	var verb: String = AFFORD_VERB_CARRY
	var priority: int = AFFORD_PRIORITY
	if _carrier != null:
		if actor != _carrier:
			return {}
		verb = AFFORD_VERB_PLACE
		# In her arms he is no longer "the thing a beat is about" fighting a
		# reachable surface for the badge -- he already IS her hands. At his own
		# band this offer's `FACING_BONUS` (she is always facing straight at
		# what she is carrying) beat a bed or a table's own PLACE/WASH every
		# time, so the badge kept re-offering to put him down where he already
		# was not, and a same-instant CARRY-then-PLACE double tap looked like
		# him being dropped the moment he was picked up. Owner bug, root cause
		# #2. Dropped to the loose-prop band: a reachable surface now wins, and
		# his own floor put-down stays the fallback when nothing else is close.
		priority = AffordanceRulesScript.PRIORITY_PROP
	elif actor.has_method("is_carrying_node") and bool(actor.call("is_carrying_node")):
		# Her hands are full of something else; nothing to offer on him.
		return {}
	elif _need == Needs.NEEDS_COMFORT or _need == Needs.CRYING:
		verb = AFFORD_VERB_HUG
	return {
		"verb": verb,
		"anchor": anchor,
		"radius": AFFORD_REACH,
		"priority": priority,
		"target": self,
	}


## The verb `perform_affordance()` actually ran last time, for
## `affordance_layer.gd` to report instead of whatever it had cached from its
## last `evaluate()` -- which can be a frame stale relative to a second call
## landing in the same instant (see `AffordanceLayer.perform()`).
var _last_performed_verb: String = ""


func get_last_performed_verb() -> String:
	return _last_performed_verb


func perform_affordance(actor: Node3D) -> bool:
	var offer: Dictionary = get_affordance(actor)
	if offer.is_empty():
		return false
	var verb: String = String(offer["verb"])
	_last_performed_verb = verb
	match verb:
		AFFORD_VERB_PLACE:
			if not actor.has_method("put_down_carried"):
				return false
			return bool(actor.call("put_down_carried"))
		AFFORD_VERB_CARRY:
			if not actor.has_method("carry_node"):
				return false
			return bool(actor.call("carry_node", self, "carryFront"))
		AFFORD_VERB_HUG:
			satisfy(_need)
			return true
	return false


## -- What the child needs -------------------------------------------------------

func get_stats() -> RefCounted:
	build()
	return _state


func get_need() -> String:
	build()
	return _need


func get_activity() -> String:
	return _activity


func get_line() -> String:
	build()
	return Needs.line_for(_need, _urgent)


## Seconds the current need has waited unanswered; 0 while content or cared for.
func get_ignored_for() -> float:
	return _ignored_for


## True once the wait has passed `child_life.gd::IGNORED_AFTER_SEC`: the bubble
## is on its louder line and the face is the `hmph`.
func is_urgent() -> bool:
	return _urgent


## Sets what the caregiver is doing with the child. An explicit activity wins
## over whatever the stats would have chosen -- that is what lets Milk Time seat
## the child even while another stat drifts, and it is the brief's "make
## transitions deliberate".
## `detail` is optional and names WHICH act it is, when the caller knows -- the
## care kind (`giveBottle`, `washFace`) is the vocabulary. It exists because
## "feeding" alone cannot tell a bottle from a spoon, and those are two different
## motions: a bottle is two hands and a head tipped back, a spoon is one hand.
##
## It defaults to "" and every existing caller passes nothing, in which case
## `child_life.gd` falls back to reading the child's own stats -- see
## `clip_for()`. `house_level_director.gd` already knows the care kind at both
## call sites and could pass it; that is a one-word change in a file this pass
## does not own, and is listed in `docs/BUNNY_LIFE_PASS.md`.
func set_activity(activity: String, detail: String = "") -> void:
	build()
	if _activity == activity and _activity_detail == detail:
		return
	_activity = activity
	_activity_detail = detail
	_refresh()


## The caregiver answered a need. Moves the stat that caused it, so the child
## stops asking -- the loop closes in the model rather than in a mission script.
func satisfy(need: String, amount: float = 60.0) -> void:
	build()
	match need:
		Needs.HUNGRY:
			_state.call("adjust", "hunger", -amount)
		Needs.THIRSTY:
			_state.call("adjust", "thirst", -amount)
		Needs.SLEEPY:
			_state.call("adjust", "energy", amount)
		Needs.DIRTY, Needs.NEEDS_BATH:
			_state.call("adjust", "cleanliness", amount)
		Needs.NEEDS_CHANGING:
			_state.call("adjust", "freshness", amount)
		Needs.NEEDS_COMFORT, Needs.WANTS_TO_PLAY, Needs.CRYING:
			_state.call("adjust", "happiness", amount)
	# Being cared for is pleasant whatever the need was.
	_state.call("adjust", "happiness", 8.0)
	# ...and the wait is over, whatever it had grown into.
	_reset_ignored()
	# ...and it SHOWS, for a few seconds. Without this the only thing that happens
	# when a child finishes a whole mission is that a bubble goes away, which is
	# the quietest possible answer to "you looked after me".
	_happy_left = Life.HAPPY_SECONDS
	_refresh()


## Convenience for the common case: answer whatever the child is asking for.
func satisfy_current(amount: float = 60.0) -> String:
	build()
	var answered: String = _need
	if answered.is_empty():
		return ""
	satisfy(answered, amount)
	return answered


## -- Presentation ---------------------------------------------------------------

func _refresh() -> void:
	if _state == null or _wrapper == null:
		return
	var described: Dictionary = Present.describe(
		_state.call("describe"), _activity, _urgent)

	var new_need: String = String(described["need"])
	if new_need != _need:
		_need = new_need
		# A new need starts a new wait; the escalation belongs to the old one.
		_reset_ignored()
		described = Present.describe(_state.call("describe"), _activity, false)
		need_changed.emit(_need)
		_say_need(_need)

	var pose: String = String(described["pose"])
	if _wrapper.has_method("set_pose") and String(_wrapper.call("get_pose")) != pose:
		_wrapper.call("set_pose", pose)
		activity_changed.emit(String(described["activity"]), pose)

	if _bubble != null:
		# Nothing to say when content: an empty bubble is quieter than a cheerful
		# one, and the child should only interrupt when it wants something. (And
		# nothing at all while suppressed -- a refresh must not re-show it.)
		_apply_bubble_visibility()
		_bubble.text = String(described["line"])
	# AFTER the text, not before it. The step aside is sized from the line's
	# rendered width (`_bubble_half_width()`), so placing first would measure the
	# PREVIOUS need's line -- and the two are not the same width.
	_place_bubble()

	# The body says the same thing the bubble does. A line that reads "I'm
	# hungry!" over a child standing perfectly still is the statue problem in one
	# frame, so the need and the motion are refreshed together, always.
	_apply_life()


## The pose currently shown, for tests and for the production report.
func get_pose() -> String:
	build()
	return String(_wrapper.call("get_pose")) if _wrapper != null else ""


## Where a bottle, a towel or a teddy should be aimed. Delegates to the wrapper's
## `LB_Rig_v1` sockets, so gameplay never names a bone -- and never returns null.
func get_socket(socket_name: String) -> Node3D:
	build()
	if _wrapper != null and _wrapper.has_method("get_socket"):
		return _wrapper.call("get_socket", socket_name)
	return self


## -- The backing shader ------------------------------------------------------------
##
## Kept in this file rather than as a `.gdshader` asset because the bubble is
## this file's, its constants above are the only thing that tune it, and every
## uniform it has is written from `_build_bubble_backing()`, `_fit_bubble_
## backing()` or `_aim_bubble_tail()` a few screens up.
##
## The vertex half is the stock Godot billboard: the model's translation with the
## main camera's rotation, so the quad faces the camera about its own origin --
## exactly what `Label3D` does with `BILLBOARD_ENABLED`, which is why the two
## stay aligned. The fragment half is a signed distance field: a rounded box
## unioned with a wedge, filled, rimmed where the distance is within `rim_width`
## of the edge, and laid over the same shape offset and blurred as a shadow.
## `fwidth()` gives the anti-aliasing width in screen pixels whatever the
## distance and resolution, so the rim is one crisp line at both viewports.
##
## `render_mode`: unshaded and every light path off, no depth WRITE (so the
## panel cannot punch a hole in geometry sorted after it), the default depth
## TEST (so a wall in front hides it, as it hides the text), `blend_mix` for the
## alpha, `cull_disabled` because a billboard's winding depends on the camera.
const BACKING_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix,
	shadows_disabled, ambient_light_disabled, specular_disabled, fog_disabled;

uniform vec2 half_size = vec2(0.40, 0.10);
uniform float corner_radius = 0.07;
uniform float rim_width = 0.011;
uniform vec4 fill_color : source_color = vec4(1.0, 0.965, 0.898, 0.94);
uniform vec4 rim_color : source_color = vec4(0.548, 0.644, 0.701, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.349, 0.259, 0.169, 0.22);
uniform vec2 shadow_offset = vec2(0.008, -0.014);
uniform float shadow_soft = 0.022;
uniform vec2 tail_base = vec2(0.0, -0.08);
uniform vec2 tail_tip = vec2(0.0, -0.165);
uniform float tail_half_base = 0.038;

varying vec2 local;

void vertex() {
	local = VERTEX.xy;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1],
		MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

float sd_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
	vec2 e0 = p1 - p0;
	vec2 e1 = p2 - p1;
	vec2 e2 = p0 - p2;
	vec2 v0 = p - p0;
	vec2 v1 = p - p1;
	vec2 v2 = p - p2;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
			vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
			vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

float sd_bubble(vec2 p) {
	float d = sd_round_box(p, half_size, corner_radius);
	vec2 a = tail_base - vec2(tail_half_base, 0.0);
	vec2 b = tail_base + vec2(tail_half_base, 0.0);
	if (distance(tail_tip, tail_base) > 0.005) {
		d = min(d, sd_triangle(p, a, b, tail_tip));
	}
	return d;
}

void fragment() {
	float d = sd_bubble(local);
	float aa = max(fwidth(d), 0.0005);
	float body = 1.0 - smoothstep(-aa, aa, d);
	float rim = smoothstep(-rim_width - aa, -rim_width + aa, d);
	vec4 panel = mix(fill_color, rim_color, rim);
	float panel_a = panel.a * body;

	float ds = sd_bubble(local - shadow_offset);
	float shadow_a = shadow_color.a * (1.0 - smoothstep(-shadow_soft * 0.5, shadow_soft, ds));

	float alpha = panel_a + shadow_a * (1.0 - panel_a);
	vec3 rgb = mix(shadow_color.rgb, panel.rgb, panel_a / max(alpha, 0.0001));
	ALBEDO = rgb;
	ALPHA = alpha;
}
"""
