extends RefCounted

const Hud := preload("res://scripts/tutor/ui/tutor_hud.gd")

func test_name() -> String:
	return "tutor_touch_targets"

func run():
	var failures: Array = []
	var hud := Hud.new()
	hud.build()
	var minimums := {"tapToTalk": 200.0, "repeat": 110.0, "card": 110.0, "mute": 120.0}
	for key: String in minimums:
		var button: Button = hud.buttons()[key]
		var expected := Vector2.ONE * float(minimums[key])
		var hit := Rect2((button.size - expected) * 0.5, expected)
		for point: Vector2 in [hit.position + Vector2.ONE, hit.end - Vector2.ONE]:
			if not button._has_point(point):
				failures.append("%s does not include its original touch margin" % key)
		if button._has_point(hit.end + Vector2.ONE):
			failures.append("%s extends beyond its declared hit area" % key)
	for frame: Vector2 in [Vector2(1334, 750), Vector2(2340, 1080)]:
		var rects := Hud.layout_rects(frame)
		for key: String in minimums:
			if rects[key].size != Vector2.ONE * float(minimums[key]):
				failures.append("%s layout audit disagrees with actual hit size" % key)
			if not Rect2(Vector2.ZERO, frame).encloses(rects[key]):
				failures.append("%s hit margin leaves the viewport" % key)
			for other: String in minimums:
				if key != other and rects[key].intersects(rects[other]):
					failures.append("%s and %s hit areas overlap" % [key, other])
	hud.free()
	return failures
