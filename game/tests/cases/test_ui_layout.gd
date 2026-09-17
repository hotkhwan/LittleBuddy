extends RefCounted

## Touch targets, safe areas and collisions on the screens outside the room.
##
## `test_ui_chrome.gd` already does this for the baby room. These three screens
## -- the title, the level summary and the sticker book -- had no geometric guard
## at all, and all three were shipping controls under the minimum:
## `session_summary` had a 180x180 close button and a 250x180 Replay; the sticker
## book's back button was 180x180.
##
## The rules, from `docs/ART_BIBLE.md` section 8:
##
##   * **240 x 240 minimum** at the 1366x1024 reference for any primary
##     child-facing control. "Never shrink this."
##   * **Every full-screen layer respects the safe area.** `Celebration` once
##     ignored it and drew a sticker card over the baby's face.
##   * Text minimum 27 pt at the reference -- a pre-reader's grown-up has to be
##     able to read it across a room.
##
## All of the geometry is computed from stored anchors, offsets and minimum
## sizes, so no viewport, layout pass or autoload is needed.

const SAFE_AREA_SCRIPT_PATH: String = "res://scripts/ui/safe_area.gd"
const SafeAreaScript := preload("res://scripts/ui/safe_area.gd")

const MENU_SCENE: String = "res://scenes/main/main.tscn"
const SUMMARY_SCENE: String = "res://scenes/progression/session_summary.tscn"
const STICKER_BOOK_SCENE: String = "res://scenes/progression/sticker_book.tscn"

## Landscape safe-area sizes in the 1366x1024 design space, for the two shapes
## the game ships on: an iPhone (~2.17:1) and an iPad (~1.44:1). Same constants
## `test_ui_chrome.gd` uses, so the two files cannot disagree about the device.
const SAFE_AREA_PHONE: Vector2 = Vector2(2170.0, 992.0)
const SAFE_AREA_TABLET: Vector2 = Vector2(1425.0, 992.0)

const MIN_TOUCH_SIDE: float = 240.0
const MIN_FONT_SIZE: int = 27

## `scene -> the node that must carry safe_area.gd`.
const SCREENS: Dictionary = {
	MENU_SCENE: "UI/SafeArea",
	SUMMARY_SCENE: "SafeArea",
	STICKER_BOOK_SCENE: "SafeArea",
}

## Controls that must not land on top of each other at either shape. Only the
## title screen needs this: the other two lay out in containers, which cannot
## overlap by construction.
const MENU_LAID_OUT_NODES: Array[String] = [
	"UI/SafeArea/TitlePanel",
	"UI/SafeArea/PlayButton",
	"UI/SafeArea/FreePlayButton",
]


func test_name() -> String:
	return "ui_layout"


func run():
	var failures: Array = []
	failures.append_array(_test_touch_targets())
	failures.append_array(_test_everything_is_inside_a_safe_area())
	failures.append_array(_test_safe_area_actually_insets())
	failures.append_array(_test_menu_has_no_collisions())
	failures.append_array(_test_text_is_big_enough())
	return failures


# ---------------------------------------------------------------------------
# Touch targets
# ---------------------------------------------------------------------------

## Every `Button` on these screens, at both shapes.
##
## A button inside a `Container` is sized by `custom_minimum_size`; one placed by
## anchors is sized by those. Both paths are checked, because both are used and
## the summary screen mixes them.
func _test_touch_targets():
	var failures: Array = []

	for scene_path: Variant in SCREENS.keys():
		var root: Node = _instantiate(String(scene_path), failures)
		if root == null:
			continue

		var buttons: Array = []
		_collect(root, "Button", buttons)
		if buttons.is_empty():
			failures.append("%s has no buttons at all" % String(scene_path))

		for node: Node in buttons:
			var button: Control = node as Control
			var name: String = String(root.get_path_to(button))
			for area: Vector2 in [SAFE_AREA_PHONE, SAFE_AREA_TABLET]:
				var side: Vector2 = _touch_size(button, area)
				if side.x + 0.5 < MIN_TOUCH_SIDE or side.y + 0.5 < MIN_TOUCH_SIDE:
					failures.append(
						"%s: %s is %.0f x %.0f at %s. ART_BIBLE.md section 8 sets a %.0f x %.0f "
						% [String(scene_path).get_file(), name, side.x, side.y, str(area),
							MIN_TOUCH_SIDE, MIN_TOUCH_SIDE]
						+ "minimum for a child-facing control and says never to shrink it.")

		root.free()

	return failures


## The rect a control occupies: its own minimum when a container will grow it to
## that, or its stored anchors and offsets when it places itself.
static func _touch_size(control: Control, parent_size: Vector2) -> Vector2:
	if control.get_parent() is Container:
		return control.custom_minimum_size
	var rect: Rect2 = _stored_rect(control, parent_size)
	return Vector2(maxf(rect.size.x, control.custom_minimum_size.x),
			maxf(rect.size.y, control.custom_minimum_size.y))


# ---------------------------------------------------------------------------
# Safe area
# ---------------------------------------------------------------------------

## Two halves of the same rule: the screen HAS a safe area, and everything the
## child touches is UNDER it.
##
## Moving one button out to the scene root is the easy mistake -- it looks
## identical in the editor on a desktop-shaped window and puts the control under
## the Dynamic Island on a phone.
func _test_everything_is_inside_a_safe_area():
	var failures: Array = []

	for scene_path: Variant in SCREENS.keys():
		var path: String = String(scene_path)
		var root: Node = _instantiate(path, failures)
		if root == null:
			continue

		var area: Control = root.get_node_or_null(NodePath(String(SCREENS[scene_path]))) as Control
		if area == null:
			failures.append("%s has no %s node" % [path.get_file(), String(SCREENS[scene_path])])
			root.free()
			continue

		var script: Script = area.get_script() as Script
		if script == null or script.resource_path != SAFE_AREA_SCRIPT_PATH:
			failures.append("%s: %s does not carry safe_area.gd, so nothing insets it on a notched device"
					% [path.get_file(), String(SCREENS[scene_path])])

		# Full rect in the stored scene. An anchor left at 0 here is the trap the
		# art bible names: the node ends up zero-sized and silently takes its
		# whole subtree off screen.
		for entry: Array in [["anchor_left", area.anchor_left, 0.0],
				["anchor_top", area.anchor_top, 0.0],
				["anchor_right", area.anchor_right, 1.0],
				["anchor_bottom", area.anchor_bottom, 1.0]]:
			if not is_equal_approx(float(entry[1]), float(entry[2])):
				failures.append("%s: the safe area's %s is %.2f, expected %.2f -- it is not a full-rect layer"
						% [path.get_file(), String(entry[0]), float(entry[1]), float(entry[2])])

		var touchables: Array = []
		_collect(root, "Button", touchables)
		for node: Node in touchables:
			if not area.is_ancestor_of(node):
				failures.append(
					"%s: %s sits outside the safe area. " % [path.get_file(), String(root.get_path_to(node))]
					+ "On a notched device it lands under the Dynamic Island or the home indicator.")

		root.free()

	return failures


## The behaviour, not just the anchors: a laid-out `SafeArea` must come out
## non-zero and inset on all four sides.
##
## `_ready()` is invoked by hand because the headless runner never ticks a frame,
## so it never fires for a node added under the root -- the same reason
## `session_summary.gd` has `_ensure_resolved()`.
func _test_safe_area_actually_insets():
	var failures: Array = []

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return ["ui_layout: no SceneTree root; cannot lay out a SafeArea"]

	var host: Control = Control.new()
	tree.root.add_child(host)
	# After `add_child`: a Control entering a Window is laid out against it, which
	# would overwrite a size set beforehand.
	host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	host.size = Vector2(1366.0, 1024.0)

	var area: Control = SafeAreaScript.new()
	host.add_child(area)
	area.call("_ready")

	var margin: float = float(SafeAreaScript.MIN_MARGIN)
	var margin_h: float = float(SafeAreaScript.MIN_MARGIN_HORIZONTAL)

	# Read from the anchors and offsets the node now holds, not from `size`:
	# Godot defers the layout pass, and the runner never ticks a frame, so
	# `area.size` still reads (0, 0) here however correct the anchors are.
	var rect: Rect2 = _stored_rect(area, host.size)

	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		failures.append(
			"a laid-out SafeArea is %s -- zero-sized, so every child of it is invisible. "
			% str(rect.size)
			+ "This is the set_anchors_preset()/keep_offsets trap from ART_BIBLE.md section 8.")
	else:
		if not is_equal_approx(rect.size.x, host.size.x - margin_h * 2.0):
			failures.append("a laid-out SafeArea is %.0f wide inside %.0f; expected %.0f of horizontal inset each side"
					% [rect.size.x, host.size.x, margin_h])
		if not is_equal_approx(rect.size.y, host.size.y - margin * 2.0):
			failures.append("a laid-out SafeArea is %.0f tall inside %.0f; expected %.0f of vertical inset each side"
					% [rect.size.y, host.size.y, margin])
		if rect.position.x < margin_h - 0.5 or rect.position.y < margin - 0.5:
			failures.append(
				"a laid-out SafeArea starts at %s; it is hugging the bezel. %s"
				% [str(rect.position),
					"MIN_MARGIN exists so no control ever touches a rounded corner."])

	if area.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		failures.append("the SafeArea eats touches; it is a layout wrapper and must pass them through")

	host.queue_free()
	return failures


# ---------------------------------------------------------------------------
# Title screen collisions
# ---------------------------------------------------------------------------

func _test_menu_has_no_collisions():
	var failures: Array = []

	var root: Node = _instantiate(MENU_SCENE, failures)
	if root == null:
		return failures

	for area: Vector2 in [SAFE_AREA_PHONE, SAFE_AREA_TABLET]:
		var rects: Dictionary = {}
		for node_path: String in MENU_LAID_OUT_NODES:
			var control: Control = root.get_node_or_null(NodePath(node_path)) as Control
			if control == null:
				failures.append("the title screen has no %s" % node_path)
				continue
			rects[node_path] = _stored_rect(control, area)

		var names: Array = rects.keys()
		for i: int in range(names.size()):
			var rect: Rect2 = rects[names[i]]
			if not Rect2(Vector2.ZERO, area).encloses(rect):
				failures.append("at %s, %s (%s) escapes the safe area"
						% [str(area), String(names[i]), str(rect)])
			for j: int in range(i + 1, names.size()):
				if rect.intersects(rects[names[j]]):
					failures.append("at %s, %s overlaps %s"
							% [str(area), String(names[i]), String(names[j])])

	root.free()
	return failures


# ---------------------------------------------------------------------------
# Type size
# ---------------------------------------------------------------------------

func _test_text_is_big_enough():
	var failures: Array = []

	for scene_path: Variant in SCREENS.keys():
		var path: String = String(scene_path)
		var root: Node = _instantiate(path, failures)
		if root == null:
			continue

		var labels: Array = []
		_collect(root, "Label", labels)
		for node: Node in labels:
			var label: Label = node as Label
			var size: int = label.get_theme_font_size("font_size")
			if size > 0 and size < MIN_FONT_SIZE:
				failures.append("%s: %s is set at %d pt; ART_BIBLE.md section 8 sets a %d pt floor"
						% [path.get_file(), String(root.get_path_to(label)), size, MIN_FONT_SIZE])

		root.free()

	return failures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _instantiate(path: String, failures: Array) -> Node:
	if not ResourceLoader.exists(path):
		failures.append("%s does not exist" % path)
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null or not packed.can_instantiate():
		failures.append("%s cannot be instantiated (broken resource reference?)" % path)
		return null
	var root: Node = packed.instantiate()
	if root == null:
		failures.append("%s did not instantiate" % path)
	return root


## Every descendant of `node` whose class is (or derives from) `type`.
func _collect(node: Node, type: String, into: Array) -> void:
	if node.is_class(type):
		into.append(node)
	for child: Node in node.get_children():
		_collect(child, type, into)


## The rect a Control will occupy inside a parent of `parent_size`, from the
## anchors and offsets stored in the scene -- no layout pass required.
static func _stored_rect(control: Control, parent_size: Vector2) -> Rect2:
	var left: float = control.anchor_left * parent_size.x + control.offset_left
	var top: float = control.anchor_top * parent_size.y + control.offset_top
	var right: float = control.anchor_right * parent_size.x + control.offset_right
	var bottom: float = control.anchor_bottom * parent_size.y + control.offset_bottom
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))
