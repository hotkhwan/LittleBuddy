extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var client := VoiceClient.new()
	root.add_child(client)
	_check(not client.is_allowed(), "child audio defaults OFF")
	client.configure_gate(false, true)
	_check(not client.is_allowed(), "consent cannot override launch flag")
	client.configure_gate(true, false)
	_check(not client.is_allowed(), "launch flag cannot override consent")
	client.configure_gate(false, false, true)
	_check(client.is_allowed(), "synthetic/adult QA is available with explicit QA mode")
	_check(client.connect_session("https://invalid", "session", "cloudflare") == ERR_INVALID_PARAMETER, "requires secure WebSocket")
	client.configure_gate(false, false)
	_check(client.connect_session("wss://example.invalid", "session", "cloudflare") == ERR_UNAUTHORIZED, "disabled gate prevents socket creation")
	client.queue_free()
	if failures.is_empty():
		print("VOICE_CLIENT_TEST PASS 6")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

