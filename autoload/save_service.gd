extends Node

signal autosave_finished(reason: StringName, result: MireTypes.ActionResult)
signal settings_changed(settings: Dictionary)
signal load_finished(result: MireTypes.ActionResult)

const DEFAULT_SETTINGS := SettingsValidation.DEFAULTS
var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
# Test seam: return true for an I/O stage to simulate its failure.
var write_fault: Callable
var settings_status: MireTypes.ActionResult
var _player: MirePlayer
var _router: WorldRouter
var _loading: bool = false
var _writing: bool = false
var _generation: int = 0
var _autosave_reasons: Dictionary = {}
var _autosave_failed: bool = false
var _ending_receipt: String = ""
var _failed_ending_receipt: String = ""
var _ending_released: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100
	settings_status = load_settings()

func bind_runtime(player: MirePlayer, router: WorldRouter) -> MireTypes.ActionResult:
	if _loading or not is_instance_valid(player) or not is_instance_valid(router) or router.player != player:
		return MireTypes.failure(&"invalid_runtime", &"Save and load need the active player and world router.")
	unbind_runtime()
	_player = player
	_router = router
	GameSession.quests.autosave_requested.connect(request_autosave)
	GameSession.recovery.autosave_requested.connect(request_autosave)
	_router.autosave_requested.connect(request_autosave)
	EventBus.choice_committed.connect(_choice_committed)
	return MireTypes.success()

func unbind_runtime() -> void:
	_generation += 1
	if GameSession.quests != null and GameSession.quests.autosave_requested.is_connected(request_autosave):
		GameSession.quests.autosave_requested.disconnect(request_autosave)
	if GameSession.recovery != null and GameSession.recovery.autosave_requested.is_connected(request_autosave):
		GameSession.recovery.autosave_requested.disconnect(request_autosave)
	if is_instance_valid(_router) and _router.autosave_requested.is_connected(request_autosave):
		_router.autosave_requested.disconnect(request_autosave)
	if EventBus.choice_committed.is_connected(_choice_committed):
		EventBus.choice_committed.disconnect(_choice_committed)
	_player = null
	_router = null
	_clear_pending()

func save_slot(slot_id: StringName) -> MireTypes.ActionResult:
	if slot_id not in SaveCodec.SLOTS:
		return MireTypes.failure(&"invalid_slot", &"Choose one of the four save slots.")
	var safe := save_availability()
	if not safe.ok:
		return safe
	var snapshot: Dictionary = GameSession.snapshot()
	var scene_id := String(_router.loaded_scene_id)
	snapshot.player.scene_id = scene_id
	snapshot.player.position = ContentDB.map.scenes[scene_id].safe_anchor.duplicate()
	snapshot.player.yaw = 0.0
	var encoded := SaveCodec.encode(snapshot, slot_id, Time.get_unix_time_from_system(), ContentDB)
	if not encoded.ok:
		return encoded
	_writing = true
	var result := SaveCodec.write_file(slot_path(slot_id), encoded.payload.text, _decode.bind(slot_id), write_fault)
	_writing = false
	if result.ok:
		result.payload = encoded.payload.envelope.slot.duplicate(true)
		result.payload["timestamp"] = encoded.payload.envelope.timestamp
		EventBus.save_completed.emit(slot_id)
	return result

func save_availability() -> MireTypes.ActionResult:
	if _loading or _writing or GameSession.transactions.active or GameSession.travelling:
		return MireTypes.failure(&"busy", &"Wait for the current save, load, transaction or journey to finish.")
	if not GameSession.active or not is_instance_valid(_player) or not is_instance_valid(_router) or _router.loaded_scene_id.is_empty() or not is_instance_valid(_router.current_world):
		return MireTypes.failure(&"unavailable", &"Enter the world before saving.")
	if float(GameSession.state.player.health) <= 0:
		return MireTypes.failure(&"dead", &"Recover before saving.")
	if GameSession.action_locked or GameSession.recovery.is_consuming() or GameSession.recovery.has_pending_recovery() or _player.combat.is_committed() or _player.combat.guard_held:
		return MireTypes.failure(&"action_locked", &"Finish the current action before saving.")
	if _router.is_dangerous():
		return MireTypes.failure(&"danger", &"Move away from danger before saving.")
	return MireTypes.success()

func load_slot(slot_id: StringName, use_backup: bool = false) -> MireTypes.ActionResult:
	var inspected := inspect_slot(slot_id, use_backup)
	if not inspected.ok:
		return inspected
	var result: MireTypes.ActionResult = await _restore_candidate(inspected.payload.snapshot)
	if result.ok:
		result.payload["slot_id"] = String(slot_id)
		result.payload["recovered_backup"] = use_backup
	load_finished.emit(result)
	return result

func inspect_slot(slot_id: StringName, use_backup: bool = false) -> MireTypes.ActionResult:
	if slot_id not in SaveCodec.SLOTS:
		return MireTypes.failure(&"invalid_slot", &"Choose one of the four save slots.")
	var result := SaveCodec.read_file(slot_path(slot_id, use_backup), _decode.bind(slot_id))
	result.payload.erase("text")
	if result.ok:
		result.payload["recovered_backup"] = use_backup
	elif not use_backup:
		var backup := SaveCodec.read_file(slot_path(slot_id, true), _decode.bind(slot_id))
		if backup.ok:
			return MireTypes.ActionResult.new(false, &"backup_available", &"The main save is unavailable. A valid backup can be recovered if you choose it.", {"slot_id": String(slot_id), "primary_code": String(result.code), "backup": backup.payload.metadata, "backup_timestamp": backup.payload.timestamp})
	return result

func list_slots() -> Array:
	var rows: Array[Dictionary] = []
	for slot_id: StringName in SaveCodec.SLOTS:
		var inspected := inspect_slot(slot_id)
		var row := {"id": String(slot_id), "valid": inspected.ok, "code": String(inspected.code), "message": String(inspected.message_key), "empty": inspected.code == &"empty_slot"}
		if inspected.ok:
			row.merge(inspected.payload.metadata, true)
			row["timestamp"] = inspected.payload.timestamp
		elif inspected.code == &"backup_available":
			row["backup"] = inspected.payload.backup.duplicate(true)
			row["backup_timestamp"] = inspected.payload.backup_timestamp
		rows.append(row)
	return rows

func continue_slot() -> MireTypes.ActionResult:
	var selected: Dictionary = {}
	var skipped: Array[String] = []
	for row: Dictionary in list_slots():
		if row.valid and (selected.is_empty() or float(row.timestamp) > float(selected.timestamp)):
			selected = row
		elif not row.valid and not row.empty:
			skipped.append(row.id)
	if selected.is_empty():
		return MireTypes.ActionResult.new(false, &"no_valid_save", &"No valid main save is available. Check Load Game for recoverable backups.", {"skipped": skipped})
	return MireTypes.success({"slot_id": selected.id, "metadata": selected, "skipped": skipped, "notice": "Unavailable saves were skipped: " + ", ".join(skipped) if not skipped.is_empty() else ""})

func start_new_game(confirm_replace_autosave: bool = false) -> MireTypes.ActionResult:
	if not confirm_replace_autosave and (FileAccess.file_exists(slot_path(&"autosave")) or FileAccess.file_exists(slot_path(&"autosave", true))):
		return MireTypes.failure(&"confirmation_required", &"Starting a new game will replace the autosave. Manual saves are kept.")
	var result: MireTypes.ActionResult = await _restore_candidate(GameSession.fresh_snapshot())
	if result.ok:
		request_autosave(&"new_game")
	return result

func leave_session() -> MireTypes.ActionResult:
	if _loading or _writing or GameSession.travelling or GameSession.transactions.active:
		return MireTypes.failure(&"busy", &"Wait for the current operation before returning to the title.")
	unbind_runtime()
	GameSession.recovery.unbind_runtime()
	GameSession.new_game()
	GameSession.active = false
	return MireTypes.success()

func is_loading() -> bool:
	return _loading

func request_autosave(reason: StringName) -> void:
	if is_instance_valid(_router) and not _loading and not reason.is_empty():
		_autosave_reasons[String(reason)] = true
		_autosave_failed = false

func pending_autosave() -> Dictionary:
	return {"pending": not _autosave_reasons.is_empty(), "failed": _autosave_failed, "reasons": _autosave_reasons.keys(), "ending_ready": _ending_released}

func retry_autosave() -> MireTypes.ActionResult:
	if _autosave_reasons.is_empty():
		return MireTypes.failure(&"no_pending_save", &"There is no queued autosave to retry.")
	return _flush_autosave()

func continue_without_saving() -> MireTypes.ActionResult:
	if _failed_ending_receipt.is_empty() or _failed_ending_receipt != _current_ending_receipt() or _ending_released:
		return MireTypes.failure(&"unavailable", &"Only a failed save of this confirmed ending can be continued without saving.")
	_ending_released = true
	_failed_ending_receipt = ""
	_autosave_reasons.erase("ending")
	# Keep unrelated work queued, but this explicit bypass does not retry it.
	_autosave_failed = not _autosave_reasons.is_empty()
	return MireTypes.success({"ending_ready": true, "saved": false})

func _physics_process(_delta: float) -> void:
	if not _autosave_reasons.is_empty() and not _autosave_failed and save_availability().ok:
		_flush_autosave()

func _flush_autosave() -> MireTypes.ActionResult:
	var safe := save_availability()
	if not safe.ok:
		return safe
	var ending: bool = _autosave_reasons.has("ending") and not _ending_receipt.is_empty() and _ending_receipt == _current_ending_receipt()
	var reason: StringName = &"ending" if ending else StringName(_autosave_reasons.keys()[0])
	var result := save_slot(&"autosave")
	_autosave_failed = not result.ok
	if result.ok:
		_autosave_reasons.clear()
		_failed_ending_receipt = ""
		if ending:
			_ending_released = true
			result.payload["ending_ready"] = true
	elif ending:
		_failed_ending_receipt = _ending_receipt
		result.payload["ending_save_failed"] = true
	autosave_finished.emit(reason, result)
	return result

func _choice_committed(choice_id: StringName, _value: StringName) -> void:
	if choice_id == &"ending":
		_ending_receipt = _current_ending_receipt()
		_ending_released = false
		request_autosave(&"ending")

func _current_ending_receipt() -> String:
	if GameSession.state.choices.ending == "none":
		return ""
	var receipt: Dictionary = GameSession.state.transactions.get(String(QuestPredicates.completion_id(QuestPredicates.MQ06)), {})
	return SaveCodec.canonical(receipt) if not receipt.is_empty() else ""

func _restore_candidate(snapshot: Dictionary) -> MireTypes.ActionResult:
	if _loading or _writing or not is_instance_valid(_router):
		return MireTypes.failure(&"unavailable", &"A world router must be ready before loading.")
	var available := _load_availability()
	if not available.ok:
		return available
	var checked := SaveCodec.validate_snapshot(snapshot, ContentDB)
	if not checked.ok:
		return checked
	_loading = true
	var generation := _generation
	var router: WorldRouter = _router
	var prepared: MireTypes.ActionResult = await router.prepare_restore(snapshot.duplicate(true))
	if not prepared.ok:
		_loading = false
		return prepared
	var token := StringName(prepared.payload.prepared_token)
	if generation != _generation or not is_instance_valid(router):
		if is_instance_valid(router):
			router.discard_prepared(token)
		_loading = false
		return MireTypes.failure(&"cancelled", &"The session changed while loading.")
	available = _load_availability()
	if not available.ok:
		router.discard_prepared(token)
		_loading = false
		return available
	var requested := router.commit_restore(token)
	if not requested.ok:
		router.discard_prepared(token)
		_loading = false
		return requested
	var result: MireTypes.ActionResult = requested
	if requested.payload.get("pending", false):
		while true:
			var completed: Array = await router.travel_completed
			if String(completed[0]) == String(requested.payload.operation_id):
				result = completed[1]
				break
	_loading = false
	if result.ok:
		_clear_pending()
	return result

func _load_availability() -> MireTypes.ActionResult:
	if GameSession.transactions.active or GameSession.travelling or GameSession.action_locked or GameSession.recovery.is_consuming() or GameSession.recovery.has_pending_recovery():
		return MireTypes.failure(&"busy", &"Finish the current action or journey before loading.")
	if GameSession.active and is_instance_valid(_player) and is_instance_valid(_router.current_world):
		if _player.combat.is_committed() or _player.combat.guard_held or _router.is_dangerous():
			return MireTypes.failure(&"danger", &"Leave combat and finish the current action before loading.")
	return MireTypes.success()

func _clear_pending() -> void:
	_autosave_reasons.clear()
	_autosave_failed = false
	_ending_receipt = ""
	_failed_ending_receipt = ""
	_ending_released = false

func slot_path(slot_id: StringName, backup: bool = false) -> String:
	if slot_id not in SaveCodec.SLOTS:
		return ""
	var base := OS.get_environment("MIREWARD_TEST_SAVE_DIR")
	var directory := base.path_join("saves") if not base.is_empty() else "user://saves"
	return directory.path_join(String(slot_id) + ".json" + (".bak" if backup else ""))

func settings_path() -> String:
	var base := OS.get_environment("MIREWARD_TEST_SAVE_DIR")
	return base.path_join("settings.json") if not base.is_empty() else "user://settings.json"

func save_settings(candidate: Dictionary) -> MireTypes.ActionResult:
	var checked := SettingsValidation.validate(candidate)
	if not checked.ok:
		return checked
	var text := JSON.stringify({"schema_version": 1, "settings": candidate}, "", true, true)
	var written := SaveCodec.write_file(settings_path(), text, _decode_settings, write_fault)
	if not written.ok:
		return written
	settings = checked.payload.settings.duplicate(true)
	SettingsValidation.apply_bindings(settings)
	settings_changed.emit(settings.duplicate(true))
	return MireTypes.success()

func load_settings(use_backup: bool = false) -> MireTypes.ActionResult:
	var read := SaveCodec.read_file(settings_path() + (".bak" if use_backup else ""), _decode_settings)
	if read.ok:
		settings = read.payload.settings.duplicate(true)
		SettingsValidation.apply_bindings(settings)
		settings_changed.emit(settings.duplicate(true))
	elif read.code == &"empty_slot" and not use_backup:
		settings = DEFAULT_SETTINGS.duplicate(true)
		SettingsValidation.apply_bindings(settings)
		return MireTypes.success({"defaults": true})
	return read

func rebind(action: StringName, binding: Dictionary, swap: bool = false) -> MireTypes.ActionResult:
	var bindings := SettingsValidation.default_bindings()
	bindings.merge(settings.bindings, true)
	if not bindings.has(String(action)) or not SettingsValidation.valid_binding(binding):
		return MireTypes.failure(&"invalid_binding", &"Choose a supported action and key or mouse button.")
	var old: Dictionary = bindings[String(action)].duplicate(true)
	var conflict: String = ""
	for other: String in bindings:
		if other != String(action) and bindings[other] == binding:
			conflict = other
	if not conflict.is_empty() and not swap:
		return MireTypes.ActionResult.new(false, &"binding_conflict", &"That input is already assigned. Swap the bindings or cancel.", {"action": String(action), "conflict": conflict})
	var candidate := settings.duplicate(true)
	candidate.bindings[String(action)] = binding.duplicate(true)
	if not conflict.is_empty():
		candidate.bindings[conflict] = old
	return save_settings(candidate)

func _decode(text: String, slot_id: StringName) -> MireTypes.ActionResult:
	return SaveCodec.decode(text, slot_id, ContentDB)

func _decode_settings(text: String) -> MireTypes.ActionResult:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return MireTypes.failure(&"invalid_settings", &"The settings file is damaged or uses an unsupported version.")
	var decoded: Variant = parser.data
	if not decoded is Dictionary or not SessionValidation.whole(decoded.get("schema_version")) or int(decoded.schema_version) != 1 or not decoded.get("settings") is Dictionary:
		return MireTypes.failure(&"invalid_settings", &"The settings file is damaged or uses an unsupported version.")
	return SettingsValidation.validate(decoded.settings)
