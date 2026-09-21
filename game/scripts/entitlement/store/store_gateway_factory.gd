extends RefCounted

## Picks the gateway for the platform this build is running on.
##
##   iOS      -> `apple_store_gateway.gd`  (reports unavailable until the plugin ships)
##   Android  -> `google_play_gateway.gd`  (same)
##   anything else (macOS, Windows, Linux, the test runner) -> the deterministic mock
##
## The mock on desktop is not a loophole: its `purchase()` goes through the same
## base-class flag check and returns `disabled` in every committed build, and the
## receipt it would mint is accepted by the backend only in DEV_MODE.

const AppleGateway := preload("res://scripts/entitlement/store/apple_store_gateway.gd")
const GoogleGateway := preload("res://scripts/entitlement/store/google_play_gateway.gd")
const MockGateway := preload("res://scripts/entitlement/store/mock_store_gateway.gd")


static func for_platform(os_name: String = OS.get_name()) -> RefCounted:
	match os_name:
		"iOS":
			return AppleGateway.new()
		"Android":
			return GoogleGateway.new()
		_:
			return MockGateway.new()


static func gateway_id_for_platform(os_name: String = OS.get_name()) -> String:
	return String(for_platform(os_name).call("gateway_id"))
