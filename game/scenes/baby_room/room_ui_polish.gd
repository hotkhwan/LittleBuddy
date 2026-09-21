extends "res://scripts/ui/safe_area.gd"

## Presentation only: node paths, gameplay callbacks and hit rectangles remain
## owned by BabyRoom. Smaller painted cards never mean smaller touch targets.
const Type := preload("res://scripts/ui/typography.gd")

func _ready() -> void:
	super._ready()
	for path: String in ["StickerButton", "NextButton", "MicButton"]:
		var button := get_node(path) as Button
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := button.get_theme_stylebox(state).duplicate() as StyleBox
			for side: String in ["left", "top", "right", "bottom"]:
				style.set("expand_margin_" + side, -24.0)
			button.add_theme_stylebox_override(state, style)
		for child: Node in button.get_children():
			if child is TextureRect:
				child.offset_left = -38.0
				child.offset_right = 38.0
				child.offset_top = 42.0 if path != "MicButton" else 58.0
				child.offset_bottom = child.offset_top + 76.0
			elif child is Label:
				Type.apply(child, Type.BUTTON, false)
				child.offset_top = 112.0 if path != "MicButton" else 148.0
				child.offset_bottom = child.offset_top + 42.0
	Type.apply($StarCounter/StarCountLabel, Type.COUNT, false)
	Type.apply($TopStack/SpeechBubble/SpeechBubbleVBox/PromptLabel, Type.SECTION)
	Type.apply($TopStack/SpeechBubble/SpeechBubbleVBox/ThaiHintLabel, Type.HELPER)
	Type.apply($LevelChapterLabel, Type.HELPER)
	Type.apply($ListeningLabel, Type.BODY)
	Type.apply($EncouragementLabel, Type.SECTION)
