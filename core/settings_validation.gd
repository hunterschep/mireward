class_name SettingsValidation
extends RefCounted

const DEFAULTS := {"mouse_sensitivity": 0.002, "invert_y": false, "fov": 75.0, "view_bob": 0.02, "camera_shake": true, "text_scale": 1.0, "render_mode": "retro", "shadows": "low", "fullscreen": false, "vsync": true, "master_volume": 0.8, "ambience_volume": 0.7, "effects_volume": 0.8, "ui_volume": 0.65, "music_volume": 0.35, "bindings": {}, "dismissed_hints": []}
const RANGES := {"mouse_sensitivity": [0.0001, 0.02], "fov": [60.0, 95.0], "view_bob": [0.0, 0.08], "master_volume": [0.0, 1.0], "ambience_volume": [0.0, 1.0], "effects_volume": [0.0, 1.0], "ui_volume": [0.0, 1.0], "music_volume": [0.0, 1.0]}

static func validate(candidate: Dictionary) -> MireTypes.ActionResult:
	if not SessionValidation.json_safe(candidate) or candidate.size() != DEFAULTS.size():
		return _invalid("Settings have unknown or missing fields.")
	for key: String in DEFAULTS:
		if not candidate.has(key):
			return _invalid("A setting is missing: " + key)
	for key: String in RANGES:
		if not SessionValidation.number(candidate[key]) or float(candidate[key]) < RANGES[key][0] or float(candidate[key]) > RANGES[key][1]:
			return _invalid("Setting is outside its allowed range: " + key)
	for key: String in ["invert_y", "camera_shake", "fullscreen", "vsync"]:
		if not candidate[key] is bool:
			return _invalid("Setting must be true or false: " + key)
	if not SessionValidation.number(candidate.text_scale) or float(candidate.text_scale) not in [1.0, 1.25, 1.5] or not candidate.render_mode is String or candidate.render_mode not in ["retro", "native"] or not candidate.shadows is String or candidate.shadows not in ["low", "high", "off"]:
		return _invalid("Choose a supported text scale or rendering option.")
	if not candidate.bindings is Dictionary or not candidate.dismissed_hints is Array:
		return _invalid("Bindings and hints have invalid types.")
	var hints: Dictionary = {}
	for hint: Variant in candidate.dismissed_hints:
		if not SessionValidation.identifier(hint) or hints.has(hint):
			return _invalid("Hint identities must be unique text.")
		hints[hint] = true
	var bindings := default_bindings()
	for action: String in candidate.bindings:
		if not bindings.has(action) or not valid_binding(candidate.bindings[action]):
			return _invalid("Invalid input binding: " + action)
		bindings[action] = candidate.bindings[action]
	var assigned: Dictionary = {}
	for action: String in bindings:
		var binding: Dictionary = bindings[action]
		if action != "pause" and binding.type == "key" and int(binding.code) == KEY_ESCAPE:
			return _invalid("Escape is reserved for pause and Back.")
		var identity: String = String(binding.type) + "/" + str(int(binding.code))
		if assigned.has(identity):
			return MireTypes.ActionResult.new(false, &"binding_conflict", &"That input is already assigned. Swap the bindings or cancel.", {"action": action, "conflict": assigned[identity]})
		assigned[identity] = action
	var normalized := candidate.duplicate(true)
	for key: String in RANGES:
		normalized[key] = float(normalized[key])
	normalized.text_scale = float(normalized.text_scale)
	for action: String in normalized.bindings:
		normalized.bindings[action].code = int(normalized.bindings[action].code)
	return MireTypes.success({"settings": normalized})

static func default_bindings() -> Dictionary:
	var result: Dictionary = {}
	for action: String in InputBindings.KEYS:
		result[action] = {"type": "key", "code": int(InputBindings.KEYS[action])}
	result["attack_light"] = {"type": "mouse", "code": MOUSE_BUTTON_LEFT}
	result["block"] = {"type": "mouse", "code": MOUSE_BUTTON_RIGHT}
	return result

static func valid_binding(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or not value.get("type") is String or value.type not in ["key", "mouse"] or not SessionValidation.whole(value.get("code")):
		return false
	var code: int = int(value.code)
	if value.type == "mouse":
		return code in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]
	return code > 0 and code < KEY_SPECIAL + 256 and not OS.get_keycode_string(code).is_empty() and code not in [KEY_NONE, KEY_UNKNOWN]

static func apply_bindings(settings: Dictionary) -> void:
	var bindings := default_bindings()
	bindings.merge(settings.bindings, true)
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var binding: Dictionary = bindings[action]
		var replacement: InputEvent
		if binding.type == "key":
			var key := InputEventKey.new()
			key.physical_keycode = int(binding.code)
			replacement = key
		else:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(binding.code)
			replacement = mouse
		var current := InputMap.action_get_events(action)
		# Replacing an unchanged event drops its held state in Godot's InputMap.
		if current.size() == 1 and current[0].is_match(replacement, true):
			continue
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, replacement)

static func _invalid(message: String) -> MireTypes.ActionResult:
	return MireTypes.failure(&"invalid_settings", StringName(message))
