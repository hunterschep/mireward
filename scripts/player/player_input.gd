class_name PlayerInput
extends RefCounted

const EDGE_ACTIONS: Array[StringName] = [&"attack_light", &"attack_heavy", &"block", &"interact", &"quick_heal", &"jump"]
var suppressed: bool = false

func clear_edges() -> void:
	suppressed = true

func tick() -> void:
	if not suppressed:
		return
	for action: StringName in EDGE_ACTIONS:
		if Input.is_action_pressed(action):
			return
	suppressed = false

func pressed(action: StringName) -> bool:
	return not suppressed and Input.is_action_just_pressed(action)

func held(action: StringName) -> bool:
	return not suppressed and Input.is_action_pressed(action)

func movement() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
