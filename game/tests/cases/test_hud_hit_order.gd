extends RefCounted

## OWNER PLAYTEST 2026-09-21: "the top-right icon on the Bunny-care screen does
## nothing". The care close-up is a full-rect MOUSE_FILTER_STOP control; when it
## is the later sibling of the HUD in the same CanvasLayer it wins every pick,
## so the Home button looked live and swallowed the tap. Both directors now
## raise the HUD above the close-up after mounting it. This case pushes a REAL
## touch through the viewport at the Home button's centre, in both orders.

const HudScript := preload("res://scripts/gameplay/house_hud.gd")
const CareScript := preload("res://scripts/care/care_overlay.gd")
const SIZE := Vector2(1334, 750)


func run():
	var failures: Array = []
	failures.append_array(_test_the_close_up_used_to_eat_the_tap())
	failures.append_array(_test_the_hud_on_top_takes_the_tap())
	failures.append_array(_test_both_directors_raise_the_hud())
	return failures


func _build(hud_on_top: bool) -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.gui_disable_input = false
	tree.root.add_child(viewport)
	var ui := CanvasLayer.new()
	ui.name = "UI"
	viewport.add_child(ui)
	var hud: Control = HudScript.new()
	ui.add_child(hud)
	hud.call("build")
	var care: Control = CareScript.new()
	ui.add_child(care)
	care.call("build")
	care.visible = true
	care.call("begin", "giveBottle")
	hud.call("set_narration_covered", true)
	if hud_on_top:
		ui.move_child(hud, ui.get_child_count() - 1)
	var opened: Array = []
	hud.connect("pause_opened", func() -> void: opened.append(true))
	return {"viewport": viewport, "hud": hud, "care": care, "opened": opened}


## Godot's GUI pick, mirrored. The headless runner's root is not an active
## tree: `Viewport.push_input` is refused and anchors are never resolved, so
## each Control's rect is computed here from its anchors and offsets against
## its parent's rect, and the walk is the viewport's (later siblings first,
## depth first, STOP wins, PASS keeps looking, IGNORE and hidden are skipped).
static func _rect_of(control: Control, parent_rect: Rect2) -> Rect2:
	var w: float = parent_rect.size.x
	var h: float = parent_rect.size.y
	var left: float = control.anchor_left * w + control.offset_left
	var top: float = control.anchor_top * h + control.offset_top
	var right: float = control.anchor_right * w + control.offset_right
	var bottom: float = control.anchor_bottom * h + control.offset_bottom
	if right <= left:
		right = left + maxf(control.size.x, control.custom_minimum_size.x)
	if bottom <= top:
		bottom = top + maxf(control.size.y, control.custom_minimum_size.y)
	return Rect2(parent_rect.position + Vector2(left, top), Vector2(right - left, bottom - top))


static func _pick(node: Node, at: Vector2, parent_rect: Rect2) -> Control:
	var children: Array = node.get_children()
	children.reverse()
	for child: Node in children:
		var control: Control = child as Control
		var rect: Rect2 = parent_rect
		if control != null:
			if not control.visible:
				continue
			rect = _rect_of(control, parent_rect)
		var hit: Control = _pick(child, at, rect)
		if hit != null:
			return hit
		if control == null or control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if rect.has_point(at) and control.mouse_filter == Control.MOUSE_FILTER_STOP:
			return control
	return null


func _tap(ui: Node, at: Vector2) -> Control:
	var hit: Control = _pick(ui, at, Rect2(Vector2.ZERO, SIZE))
	if hit is BaseButton:
		(hit as BaseButton).emit_signal("pressed")
	return hit


func _free(h: Dictionary) -> void:
	var viewport: SubViewport = h["viewport"]
	viewport.get_parent().remove_child(viewport)
	viewport.free()


func _test_the_close_up_used_to_eat_the_tap():
	var failures: Array = []
	var h: Dictionary = _build(false)
	var hud: Control = h["hud"]
	var centre: Vector2 = HudScript.home_button_rect(SIZE).get_center()
	var hit: Control = _tap((h["viewport"] as SubViewport).get_node("UI"), centre)
	if hit != h["care"]:
		# Documents the trap the fix removes: the later full-rect sibling wins.
		failures.append("(documentation) with the close-up mounted after the HUD the close-up should take the tap, got %s" % str(hit))
	_free(h)
	return failures


func _test_the_hud_on_top_takes_the_tap():
	var failures: Array = []
	var h: Dictionary = _build(true)
	# The close-up still gets the child's strokes: a touch in the middle is not
	# swallowed by the HUD (its root and labels are IGNORE).
	var care: Control = h["care"]
	var middle: Vector2 = SIZE * 0.5
	var under_finger: Control = _pick((h["viewport"] as SubViewport).get_node("UI"), middle, Rect2(Vector2.ZERO, SIZE))
	if under_finger == null or (under_finger != care and not care.is_ancestor_of(under_finger)):
		failures.append("a touch in the middle must still reach the close-up, got %s" % str(under_finger))
	var centre: Vector2 = HudScript.home_button_rect(SIZE).get_center()
	var hit: Control = _tap((h["viewport"] as SubViewport).get_node("UI"), centre)
	if hit == null or hit.name != "HomeButton":
		failures.append("with the HUD above the close-up the Home button must take the tap, got %s" % str(hit))
	if (h["opened"] as Array).is_empty():
		failures.append("pressing Home over the close-up must open the pause card")
	if not care.visible:
		failures.append("the close-up stays visible with the HUD above it")
	_free(h)
	return failures


## Pins the fix in both directors' source: the HUD is re-raised right after the
## care overlay is mounted.
func _test_both_directors_raise_the_hud():
	var failures: Array = []
	for path: String in ["res://scripts/gameplay/house_level_director.gd", "res://scripts/gameplay/house_freeplay_director.gd"]:
		var text: String = FileAccess.get_file_as_string(path)
		var mount: int = text.find("ui.add_child(_care_overlay)")
		if mount < 0:
			mount = text.find("ui.add_child(care)")
		var raise: int = text.find("ui.move_child(_hud, ui.get_child_count() - 1)", mount)
		if mount < 0 or raise < 0:
			failures.append("%s must raise the HUD above the care overlay after mounting it" % path)
	return failures
