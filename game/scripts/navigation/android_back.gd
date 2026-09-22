extends Node

## Android delivers system Back as a window notification. Translate it into
## the same `ui_cancel` action used by keyboard QA so overlays and scenes keep
## one tested navigation path. `quit_on_go_back=false` prevents the engine from
## exiting before that path runs.

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)

