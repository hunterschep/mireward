class_name SaveCodec
extends RefCounted
## Versioned snapshots and same-directory file replacement.

const SCHEMA_VERSION: int = 1
const CONTENT_VERSION: String = "1.0.0"
const SLOTS: Array[StringName] = [&"autosave", &"manual_1", &"manual_2", &"manual_3"]
const LOCATIONS := {"exterior": "Greyfen Vale", "interior_inn": "Brackenford Inn", "interior_crypt": "Saint Orra's Crypt", "interior_undercroft": "Rookwatch Undercroft"}
const STATE_FIELDS := ["player", "inventory", "equipment", "key_items", "evidence", "quests", "world", "choices", "discoveries", "transactions", "pending_delivery", "shop_stock", "flags", "next_stack"]

static func canonical(value: Variant) -> String:
	# JSON numbers load as floats. Normalize both sides before hashing.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)

static func validate_snapshot(snapshot: Dictionary, db: Node) -> MireTypes.ActionResult:
	var checked := SessionValidation.validate(snapshot, db)
	if not checked.ok:
		return checked
	if snapshot.size() != STATE_FIELDS.size():
		return MireTypes.failure(&"invalid_state", &"The save contains unknown session fields.")
	for key: String in STATE_FIELDS:
		if not snapshot.has(key):
			return MireTypes.failure(&"invalid_state", &"The save is missing session data.")
	var flags: Array[String] = ["puzzle_solved", "free_inn", "shelter_lights", "restored_badge", "undercroft_open"]
	if snapshot.flags.size() != flags.size():
		return MireTypes.failure(&"invalid_state", &"The save has missing or unknown world flags.")
	for flag: String in flags:
		if not snapshot.flags.get(flag) is bool:
			return MireTypes.failure(&"invalid_state", &"The save has an invalid world flag: " + flag)
	if snapshot.player.scene_id == "interior_undercroft" and not snapshot.flags.undercroft_open:
		return MireTypes.failure(&"invalid_state", &"The saved undercroft location precedes Ada opening its door.")
	var known: Dictionary = {"village_banner": true, "village_grain_tally": true, "checkpoint_notice": true, "checkpoint_toll_bar": true, "checkpoint_banner": true}
	var spawns: Dictionary = {}
	for spawn: Dictionary in db.map.spawns:
		known[spawn.id] = true
		spawns[spawn.id] = true
	for id: String in db.containers:
		known[id] = true
	for definition: MireTypes.QuestDef in db.quests.values():
		for objective: Dictionary in definition.data.objectives:
			for id: String in String(objective.target_id).split(","):
				known[id.strip_edges()] = true
	for id: String in snapshot.world:
		if not known.has(id):
			return MireTypes.failure(&"invalid_state", &"The save contains an unknown world entity: " + id)
		if (db.containers.has(id) and snapshot.world[id].get("kind") != "container") or (spawns.has(id) and snapshot.world[id].get("kind") != "corpse"):
			return MireTypes.failure(&"invalid_state", &"A saved loot source has no matching record type: " + id)
		for field: String in ["health", "stamina", "position", "instance_id", "node_path"]:
			if snapshot.world[id].has(field):
				return MireTypes.failure(&"invalid_state", &"Transient actor data cannot be saved: " + field)
	for shop: String in db.shops:
		if not snapshot.shop_stock.has(shop) or snapshot.shop_stock[shop].size() != db.shops[shop].size():
			return MireTypes.failure(&"invalid_state", &"The save is missing shop stock.")
	return QuestPredicates.validate_snapshot(snapshot, db)

static func encode(snapshot: Dictionary, slot_id: StringName, timestamp: float, db: Node) -> MireTypes.ActionResult:
	if slot_id not in SLOTS or not is_finite(timestamp) or timestamp <= 0:
		return MireTypes.failure(&"invalid_slot", &"Choose a valid save slot.")
	var checked := validate_snapshot(snapshot, db)
	if not checked.ok:
		return checked
	var payload_text := canonical(snapshot)
	var envelope := {"schema_version": SCHEMA_VERSION, "game_version": String(ProjectSettings.get_setting("application/config/version")), "content_version": CONTENT_VERSION, "timestamp": timestamp, "slot": metadata(snapshot, slot_id, db), "checksum": payload_text.sha256_text(), "payload": JSON.parse_string(payload_text)}
	return MireTypes.success({"text": JSON.stringify(envelope, "", true, true), "envelope": envelope})

static func decode(text: String, expected_slot: StringName, db: Node) -> MireTypes.ActionResult:
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return MireTypes.failure(&"corrupt_save", &"The save file is not valid JSON.")
	var envelope: Dictionary = parser.data
	if not SessionValidation.whole(envelope.get("schema_version")):
		return MireTypes.failure(&"corrupt_save", &"The save has no valid schema version.")
	if int(envelope.schema_version) != SCHEMA_VERSION:
		return MireTypes.failure(&"unsupported_schema", &"This save uses a different schema version.")
	if not envelope.get("game_version") is String or not envelope.get("content_version") is String:
		return MireTypes.failure(&"corrupt_save", &"The save version fields are invalid.")
	if envelope.game_version != String(ProjectSettings.get_setting("application/config/version")) or envelope.content_version != CONTENT_VERSION:
		return MireTypes.failure(&"incompatible_version", &"This save belongs to a different game or content version.")
	if not SessionValidation.number(envelope.get("timestamp")) or not is_finite(float(envelope.timestamp)) or float(envelope.timestamp) <= 0 or not envelope.get("slot") is Dictionary or not envelope.slot.get("id") is String or envelope.slot.id != String(expected_slot) or expected_slot not in SLOTS:
		return MireTypes.failure(&"corrupt_save", &"The save slot or timestamp is invalid.")
	if not envelope.get("payload") is Dictionary or not envelope.get("checksum") is String or not SessionValidation.json_safe(envelope):
		return MireTypes.failure(&"corrupt_save", &"The save payload is incomplete.")
	var snapshot: Dictionary = envelope.payload
	if canonical(snapshot).sha256_text() != envelope.checksum:
		return MireTypes.failure(&"checksum_mismatch", &"The save checksum does not match its contents.")
	var checked := validate_snapshot(snapshot, db)
	if not checked.ok:
		return checked
	if envelope.slot != metadata(snapshot, expected_slot, db):
		return MireTypes.failure(&"corrupt_save", &"The save metadata does not match its progress.")
	return MireTypes.success({"snapshot": snapshot.duplicate(true), "metadata": envelope.slot.duplicate(true), "timestamp": float(envelope.timestamp), "schema_version": SCHEMA_VERSION})

static func metadata(snapshot: Dictionary, slot_id: StringName, db: Node) -> Dictionary:
	var chapter: String = "The Last Toll: completed" if snapshot.choices.ending != "none" else "Bread and Iron"
	for id: StringName in db.quests:
		if String(id).begins_with("mq_") and snapshot.quests[String(id)].state != "COMPLETED":
			chapter = String(db.quests[id].data.name)
			break
	return {"id": String(slot_id), "chapter": chapter, "scene_id": snapshot.player.scene_id, "location": LOCATIONS[snapshot.player.scene_id], "ending": snapshot.choices.ending}

static func read_file(path: String, validate: Callable) -> MireTypes.ActionResult:
	if not FileAccess.file_exists(path):
		return MireTypes.failure(&"empty_slot", &"This save slot is empty.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return MireTypes.failure(&"read_failed", &"The save file could not be opened.")
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error not in [OK, ERR_FILE_EOF]:
		return MireTypes.failure(&"read_failed", &"The save file could not be read.")
	var result: MireTypes.ActionResult = validate.call(text)
	if result.ok:
		result.payload["text"] = text
	return result

static func write_file(path: String, text: String, validate: Callable, fault: Callable = Callable()) -> MireTypes.ActionResult:
	if _failed(fault, &"directory") or DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return _io_error(&"directory")
	var temporary := path + ".tmp"
	var written := _write_temporary(temporary, text, validate, fault, "temporary")
	if not written.ok:
		return written
	var previous := read_file(path, validate)
	if previous.code == &"read_failed" or (FileAccess.file_exists(path) and _failed(fault, &"existing_read")):
		DirAccess.remove_absolute(temporary)
		return _io_error(&"existing_read")
	if previous.ok:
		var backed_up := _write_temporary(path + ".bak.tmp", previous.payload.text, validate, fault, "backup")
		if not backed_up.ok:
			DirAccess.remove_absolute(temporary)
			return backed_up
		if _failed(fault, &"backup_replace") or DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
			DirAccess.remove_absolute(temporary)
			DirAccess.remove_absolute(path + ".bak.tmp")
			return _io_error(&"backup_replace")
	if _failed(fault, &"replace") or DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return _io_error(&"replace")
	return MireTypes.success()

static func _write_temporary(path: String, text: String, validate: Callable, fault: Callable, stage: String) -> MireTypes.ActionResult:
	if _failed(fault, StringName(stage + "_open")):
		return _io_error(StringName(stage + "_open"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _io_error(StringName(stage + "_open"))
	var failed_stage: StringName
	if _failed(fault, StringName(stage + "_write")):
		failed_stage = StringName(stage + "_write")
	else:
		file.store_string(text)
		if file.get_error() != OK:
			failed_stage = StringName(stage + "_write")
	if failed_stage.is_empty():
		file.flush()
		if _failed(fault, StringName(stage + "_flush")) or file.get_error() != OK:
			failed_stage = StringName(stage + "_flush")
	file.close()
	if failed_stage.is_empty():
		var checked := read_file(path, validate)
		if _failed(fault, StringName(stage + "_readback")) or not checked.ok or checked.payload.get("text", "") != text:
			failed_stage = StringName(stage + "_readback")
		elif _failed(fault, StringName(stage + "_validate")):
			failed_stage = StringName(stage + "_validate")
	if not failed_stage.is_empty():
		DirAccess.remove_absolute(path)
		return _io_error(failed_stage)
	return MireTypes.success()

static func _failed(fault: Callable, stage: StringName) -> bool:
	return fault.is_valid() and bool(fault.call(stage))

static func _io_error(stage: StringName) -> MireTypes.ActionResult:
	return MireTypes.ActionResult.new(false, &"write_failed", &"The save could not be written. Progress remains in memory; existing valid saves were not deleted.", {"stage": String(stage)})
