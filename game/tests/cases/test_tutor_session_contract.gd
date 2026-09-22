extends RefCounted

const Contract := preload("res://scripts/tutor/session/tutor_session_contract.gd")

func run():
	var failures: Array[String] = []
	var contract := Contract.new()
	if contract.child_label() != "Lesson Mode": failures.append("default mode is a local lesson")
	var ok := contract.configure({"tier": "premium", "mode": "premium_live",
		"capabilities": ["realtimeAudio", "bargeIn"], "quotaRemaining": 900,
		"audioMode": "live", "provider": "must-not-leak"})
	if not ok: failures.append("valid Premium metadata is accepted")
	if contract.metadata().has("provider"): failures.append("provider internals leaked into client metadata")
	if contract.child_label() != "Talk live with Aliz": failures.append("Premium has a child-friendly label")
	contract.fallback("live_disconnect")
	if contract.mode() != "standard_chat": failures.append("Premium falls back to Standard")
	contract.fallback("standard_unavailable")
	if contract.mode() != "lesson_local": failures.append("Standard falls back to local lessons")
	if contract.fallback("already_local"): failures.append("local mode cannot fall through")
	if contract.configure({"tier": "standard", "mode": "premium_live", "capabilities": [],
		"quotaRemaining": 1, "audioMode": "live"}): failures.append("Standard cannot claim Premium Live")
	return failures
