extends Node

signal inventory_changed
signal equipment_changed
signal currency_changed
signal entity_defeated(entity_id: StringName)
signal evidence_acquired(evidence_id: StringName)
signal quest_updated(quest_id: StringName)
signal choice_committed(choice_id: StringName, value: StringName)
signal landmark_discovered(landmark_id: StringName)
signal save_completed(slot_id: StringName)
signal mode_changed(mode: StringName)
signal session_restored
signal feedback(message: String)

func publish(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		var signal_name := StringName(event.get("name", ""))
		if not has_signal(signal_name):
			push_error("Unknown committed event: %s" % signal_name)
			continue
		var arguments: Array = [signal_name]
		arguments.append_array(event.get("args", []))
		callv("emit_signal", arguments)
