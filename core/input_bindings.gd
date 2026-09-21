class_name InputBindings
extends RefCounted

const KEYS := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "sprint": KEY_SHIFT, "jump": KEY_SPACE, "attack_heavy": KEY_R, "interact": KEY_E, "quick_heal": KEY_Q, "inventory": KEY_TAB, "journal": KEY_J, "map": KEY_M, "pause": KEY_ESCAPE}

static func install_defaults() -> void:
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, key)
	for action: String in ["attack_light", "block"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT if action == "attack_light" else MOUSE_BUTTON_RIGHT
			InputMap.action_add_event(action, mouse)

static func label(action: StringName) -> String:
	var events := InputMap.action_get_events(action)
	return events[0].as_text().replace(" (Physical)", "") if not events.is_empty() else "Unbound"
