extends Node

## ALIZ'S TALKING MOUTH -- turns a 0..1 "how open" amount into one of the four
## texture mouth frames, with the smoothing that stops it flickering.
##
## Her rig has no blend shapes and her face is a painted atlas, so the mouth
## cannot open by a continuous amount: it can show `closed` (the expression's
## own mouth), `small`, `mid` or `open` (`buddy_face.gd`'s `mouthFrames`).
## Whoever drives it -- `buddy_lip_sync.gd` from an audio envelope, or a
## caller by hand -- sets a TARGET amount; this node slews toward it (attack
## `ATTACK_SEC` from shut to wide, release `RELEASE_SEC` from wide to shut),
## picks the frame with a little hysteresis, and refuses to change frame again
## within `MIN_FRAME_HOLD_SEC` -- except to CLOSE, which is always allowed,
## because a mouth left open after the voice stopped is the visible bug and a
## frame held a few milliseconds long is not.
##
## `frame_changed` is the only output. `pink_girl_buddy.gd` connects it to the
## compositor; nothing here touches a texture. The node switches its own
## `_process` off once it is shut and idle, so she costs nothing while she
## walks the house not talking.
##
## Public: `set_speaking(active)`, `set_target(amount)`, `step(seconds)`,
## `amount()`, `frame()`, `target()`, `is_speaking()`, `set_frame_count(n)`.

signal frame_changed(frame: int)

## Seconds from fully shut to fully open, and back.
const ATTACK_SEC: float = 0.04
const RELEASE_SEC: float = 0.09
## A frame stays at least this long before the next opens further or closes
## part-way; a close to frame 0 is exempt (see the class doc).
const MIN_FRAME_HOLD_SEC: float = 0.04
## Smoothed amount at which frames 1, 2 and 3 open...
const OPEN_AT: Array[float] = [0.08, 0.30, 0.60]
## ...and how far below that they close again.
const HYSTERESIS: float = 0.03

var _frame_count: int = 4
var _speaking: bool = false
var _target: float = 0.0
var _amount: float = 0.0
var _frame: int = 0
var _since_change: float = 10.0


func _ready() -> void:
	set_process(false)


## How many frames the atlas offers, counting `closed`. 1 pins the frame at 0
## (an atlas without talk frames), and the amount still smooths for anything
## else that wants it.
func set_frame_count(count: int) -> void:
	_frame_count = maxi(1, count)
	if _frame >= _frame_count:
		_set_frame(0)


## `false` closes the mouth NOW (amount and frame to 0) and marks her silent;
## `true` only marks her speaking -- the amount is whatever the driver sets.
func set_speaking(active: bool) -> void:
	_speaking = active
	if not active:
		_target = 0.0
		_amount = 0.0
		_set_frame(0)
		set_process(false)
	else:
		set_process(true)


func is_speaking() -> bool:
	return _speaking


## The amount the driver wants, 0..1. Any positive amount means she is
## speaking, so a driver that never called `set_speaking(true)` still moves
## the mouth; the release still closes it when the driver goes quiet.
func set_target(amount: float) -> void:
	_target = clampf(amount, 0.0, 1.0)
	if _target > 0.0:
		_speaking = true
	set_process(true)


func target() -> float:
	return _target


func amount() -> float:
	return _amount


func frame() -> int:
	return _frame


func _process(delta: float) -> void:
	step(delta)


## Advances the smoothing by `seconds` and re-selects the frame. Public so a
## headless test (and `buddy_lip_sync.gd`'s envelope replay) can run it
## without a frame.
func step(seconds: float) -> void:
	_since_change += seconds
	if _target > _amount:
		_amount = move_toward(_amount, _target, seconds / ATTACK_SEC)
	else:
		_amount = move_toward(_amount, _target, seconds / RELEASE_SEC)
	var wanted: int = _frame
	while wanted < _frame_count - 1 and wanted < OPEN_AT.size() and _amount >= OPEN_AT[wanted]:
		wanted += 1
	while wanted > 0 and _amount < OPEN_AT[wanted - 1] - HYSTERESIS:
		wanted -= 1
	if wanted != _frame:
		if wanted == 0 or _since_change >= MIN_FRAME_HOLD_SEC:
			_set_frame(wanted)
	if _frame == 0 and _amount <= 0.0 and _target <= 0.0:
		set_process(false)


func _set_frame(frame: int) -> void:
	if frame == _frame:
		return
	_frame = frame
	_since_change = 0.0
	frame_changed.emit(_frame)
