class_name ParentAccountUx
extends RefCounted

## View-model only: hosts render this after their existing parental gate.
## There is intentionally no child-facing login prompt and no store launch.

const VALUE_MESSAGE := "Save progress across devices"


static func view(account_state: RefCounted) -> Dictionary:
	var linked: bool = account_state != null and bool(account_state.call("is_linked"))
	return {
		"showInChildUi": false,
		"headline": VALUE_MESSAGE,
		"linked": linked,
		"providers": [] if linked else [
			{"id": "apple", "label": "Sign in with Apple"},
			{"id": "google", "label": "Sign in with Google"},
		],
	}


static func subscription_tap(account_state: RefCounted, parent_gate_open: bool) -> Dictionary:
	if account_state == null:
		return {"allowed": false, "action": "show_parent_gate"}
	return account_state.call("subscription_action", parent_gate_open)
