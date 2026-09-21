extends Node

const DEFAULT_SETTINGS := {
	"mouse_sensitivity": 0.002, "invert_y": false, "fov": 75.0,
	"view_bob": 0.02, "camera_shake": true, "text_scale": 1.0,
	"render_mode": "retro", "shadows": "low", "fullscreen": false,
	"vsync": true, "master_volume": 0.8, "ambience_volume": 0.7,
	"effects_volume": 0.8, "ui_volume": 0.65, "music_volume": 0.35,
	"bindings": {}, "dismissed_hints": []
}

var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)

func save_slot(_slot_id: StringName) -> MireTypes.ActionResult:
	return MireTypes.failure(&"unsupported", &"Save service is not integrated yet.")

func load_slot(_slot_id: StringName) -> MireTypes.ActionResult:
	return MireTypes.failure(&"unsupported", &"Load service is not integrated yet.")

func list_slots() -> Array:
	return []
