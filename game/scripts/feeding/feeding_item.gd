extends Node3D

## One thing on the highchair tray: an apple, a banana, a cup of water or a
## bottle of milk. Built from primitives by `feeding_props.gd`; this node only
## owns the STATE a gesture changes -- peel, bites, liquid, tilt, glow -- and
## the home it glides back to.
##
## Purely presentational. Whether a delivery counts is decided by
## `feeding_table.gd` through `feeding_rules.gd`; nothing here awards anything.

const KIND_FRUIT: String = "fruit"
const KIND_DRINK: String = "drink"

## How far the peel strips fold: from wrapping the fruit to hanging down.
const PEEL_FOLD_DEG: float = 135.0
## How far the cup tips at the mouth.
const TIP_DEG: float = 72.0
## The soft ring that marks the right item in guided mode.
const GLOW_SCALE_MAX: float = 1.16

var item_id: String = ""
var kind: String = KIND_FRUIT
var home_position: Vector3 = Vector3.ZERO
var home_rotation: Vector3 = Vector3.ZERO

var peeled: bool = false
var enabled: bool = true

var _body: Node3D = null
var _peel_strips: Array = []
var _liquid: MeshInstance3D = null
var _liquid_height: float = 0.0
var _liquid_base_y: float = 0.0
var _tilt_pivot: Node3D = null
var _glow: MeshInstance3D = null
var _peel_progress: float = 0.0
var _bite_scale: float = 1.0
var _liquid_level: float = 1.0
var _tilt: float = 0.0
var _glow_tween: Tween = null


## -- Wiring, called by the builder ---------------------------------------------------

func bind_parts(body: Node3D, tilt_pivot: Node3D, peel_strips: Array = [],
		liquid: MeshInstance3D = null, liquid_height: float = 0.0, liquid_base_y: float = 0.0,
		glow: MeshInstance3D = null) -> void:
	_body = body
	_tilt_pivot = tilt_pivot
	_peel_strips = peel_strips
	_liquid = liquid
	_liquid_height = liquid_height
	_liquid_base_y = liquid_base_y
	_glow = glow
	if _glow != null:
		_glow.visible = false
	set_peel_progress(0.0)
	set_bite_scale(1.0)
	set_liquid_level(1.0)
	set_tilt(0.0)


func remember_home() -> void:
	home_position = position
	home_rotation = rotation


## -- State -------------------------------------------------------------------------------

func needs_peel() -> bool:
	return not _peel_strips.is_empty() and not peeled


## 0 = wrapped, 1 = peel hanging down.
func set_peel_progress(t: float) -> void:
	_peel_progress = clampf(t, 0.0, 1.0)
	for strip: Variant in _peel_strips:
		if strip is Node3D:
			(strip as Node3D).rotation.x = deg_to_rad(PEEL_FOLD_DEG) * _peel_progress
	if _peel_progress >= 0.999:
		peeled = true


func get_peel_progress() -> float:
	return _peel_progress


## 1 = whole, 0 = all eaten.
func set_bite_scale(s: float) -> void:
	_bite_scale = clampf(s, 0.0, 1.0)
	if _body != null:
		# Never a true zero: a zero-scale basis cannot be inverted and spams the log.
		_body.scale = Vector3.ONE * maxf(_bite_scale, 0.001)
		_body.visible = _bite_scale > 0.001


func get_bite_scale() -> float:
	return _bite_scale


## 1 = full, 0 = empty. The column shrinks from the top.
func set_liquid_level(t: float) -> void:
	_liquid_level = clampf(t, 0.0, 1.0)
	if _liquid == null:
		return
	var height: float = maxf(_liquid_height * _liquid_level, 0.002)
	_liquid.scale = Vector3(1.0, height / maxf(_liquid_height, 0.0001), 1.0)
	_liquid.position.y = _liquid_base_y + height * 0.5


func get_liquid_level() -> float:
	return _liquid_level


## 0 = upright, 1 = tipped to the mouth.
func set_tilt(t: float) -> void:
	_tilt = clampf(t, 0.0, 1.0)
	if _tilt_pivot != null:
		# Negative about X: the spout leans to -Z, into Bunny, away from the camera.
		_tilt_pivot.rotation.x = -deg_to_rad(TIP_DEG) * _tilt


func get_tilt() -> float:
	return _tilt


## Guided mode: a soft warm ring breathing under the right item.
func set_glow(on: bool) -> void:
	if _glow == null:
		return
	_glow.visible = on
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = null
	_glow.scale = Vector3.ONE
	if not on or not is_inside_tree():
		return
	_glow_tween = create_tween().set_loops()
	_glow_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glow_tween.tween_property(_glow, "scale", Vector3.ONE * GLOW_SCALE_MAX, 0.7)
	_glow_tween.tween_property(_glow, "scale", Vector3.ONE, 0.7)


func is_glowing() -> bool:
	return _glow != null and _glow.visible


## Back to exactly how it was served, for a new task or a returned item.
func reset_state() -> void:
	peeled = false
	enabled = true
	set_peel_progress(0.0)
	set_bite_scale(1.0)
	set_liquid_level(1.0)
	set_tilt(0.0)
	set_glow(false)
	visible = true
	position = home_position
	rotation = home_rotation
	scale = Vector3.ONE
