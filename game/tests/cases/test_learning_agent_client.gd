extends RefCounted

const Director := preload("res://scripts/tutor/expression/tutor_expression_director.gd")
const Router := preload("res://scripts/tutor/learning/learning_tool_router.gd")
const Response := preload("res://scripts/tutor/learning/learning_agent_response.gd")

func test_name() -> String: return "learning_agent_client"

func run():
	var failures: Array = []
	var director: Node = Director.new()
	var router: RefCounted = Router.new(director, ["milk", "apple_red"])
	var events := {"card": [], "hint": [], "star": [], "complete": [], "minigame": [], "suggest": [], "repeat": 0}
	router.card_requested.connect(func(v: String): events.card.append(v))
	router.hint_requested.connect(func(v: int): events.hint.append(v))
	router.star_requested.connect(func(v: String): events.star.append(v))
	router.lesson_completed.connect(func(v: String): events.complete.append(v))
	router.minigame_requested.connect(func(v: String): events.minigame.append(v))
	router.activity_suggested.connect(func(v: String): events.suggest.append(v))
	router.repeat_requested.connect(func(): events.repeat += 1)
	var result: Dictionary = Response.apply({"text": "Great!", "provider": "workers-ai", "retrieval": {"source": "ai-search"}, "toolCalls": [
		{"name": "show_learning_card", "arguments": {"assetId": "milk"}},
		{"name": "set_emotion", "arguments": {"emotion": "happy", "intensity": 0.8}},
		{"name": "give_hint", "arguments": {"hintLevel": 2}},
		{"name": "award_star", "arguments": {"reason": "lesson_turn"}},
		{"name": "complete_lesson", "arguments": {"result": "completed"}},
		{"name": "start_minigame", "arguments": {"activityId": "color_match"}},
		{"name": "suggest_activity", "arguments": {"activityId": "vocab_review"}},
		{"name": "repeat_prompt", "arguments": {}},
	]}, router)
	if not result.get("ok", false) or events != {"card": ["milk"], "hint": [2], "star": ["lesson_turn"], "complete": ["completed"], "minigame": ["color_match"], "suggest": ["vocab_review"], "repeat": 1}:
		failures.append("learning response did not reach the bounded classroom/expression surface")
	for unsafe: Dictionary in [
		{"name": "call_method", "arguments": {"method": "queue_free"}},
		{"name": "show_prop", "arguments": {"assetId": "../../secret"}},
		{"name": "award_star", "arguments": {"reason": "one", "amount": 999}},
	]:
		if router.apply(unsafe).get("accepted", false): failures.append("unsafe tool accepted: %s" % unsafe)
	if not Response.apply({}, router).get("fallback", false): failures.append("invalid response did not select offline fallback")
	director.free()
	return failures
