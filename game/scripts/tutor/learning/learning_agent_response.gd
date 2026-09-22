class_name LearningAgentResponse
extends RefCounted

## Validates and applies the Learning Agent envelope. Retrieval/provider
## metadata is diagnostic only; the client acts solely on whitelisted tools.

static func apply(payload: Variant, router: RefCounted) -> Dictionary:
	if typeof(payload) != TYPE_DICTIONARY:
		return {"ok": false, "fallback": true, "reason": "response:not_object"}
	var body: Dictionary = payload
	var text := String(body.get("text", body.get("speech", ""))).strip_edges().left(240)
	if text.is_empty():
		return {"ok": false, "fallback": true, "reason": "response:no_text"}
	var accepted: Array = []
	var rejected: Array = []
	var tools: Variant = body.get("toolCalls", body.get("tools", []))
	if typeof(tools) == TYPE_ARRAY:
		for entry: Variant in tools:
			if typeof(entry) != TYPE_DICTIONARY:
				rejected.append({"accepted": false, "reason": "tool:not_object"})
				continue
			var result: Dictionary = router.apply(entry)
			(accepted if bool(result.get("accepted", false)) else rejected).append(result)
	return {"ok": true, "fallback": false, "text": text, "acceptedTools": accepted, "rejectedTools": rejected}
