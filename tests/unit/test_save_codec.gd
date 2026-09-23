extends RefCounted

var t: SceneTree
var session: Node
var db: Node
var saves: Node

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	db = t.root.get_node("ContentDB")
	saves = t.root.get_node("SaveService")
	session.new_game()
	_roundtrips()
	_malformed()
	_file_failures()
	_slot_inspection()
	_settings()
	await _held_inputs()
	session.new_game()

func _decode(text: String) -> MireTypes.ActionResult:
	return SaveCodec.decode(text, &"manual_1", db)

func _roundtrips() -> void:
	var fixture: Script = load("res://tests/unit/test_quests.gd")
	for ending: StringName in [&"none", &"charter", &"warden", &"free_road"]:
		t.check(fixture.ending_checkpoint(session, ending, &"restitution").ok, "R37 construct genuine ending fixture " + String(ending))
		for index: int in range(16 - session.state.inventory.size()):
			t.check(session.inventory.try_add(&"arming_sword", 1, StringName("save/fill/" + str(index))).ok, "R37 fill inventory through real item APIs")
		t.check(session.quests.activate(&"sq_01_a_smiths_hand").ok, "R37 accept side quest before save")
		t.check(session.world_state.take_loot(&"kiln_hammer_crate", &"smith_hammer", 1, &"save/hammer").ok, "R37 acquire real side quest evidence")
		t.check(session.quests.complete(&"sq_01_a_smiths_hand", &"save/turnin").ok and not session.state.pending_delivery.is_empty(), "R37 genuine overflow reward is pending")
		t.check(session.world_state.mark_defeated(&"south_cart_cutpurse_01").ok, "R37 mark real authored hostile defeated")
		t.check(session.world_state.take_crowns(&"south_cart_cutpurse_01", &"save/corpse").ok, "R37 loot real corpse before save")
		var before: Dictionary = session.snapshot()
		var encoded := SaveCodec.encode(before, &"manual_1", 100.25, db)
		t.check(encoded.ok, "R37 encode all domains and " + String(ending))
		if not encoded.ok:
			continue
		var decoded := _decode(encoded.payload.text)
		t.check(decoded.ok and SaveCodec.canonical(decoded.payload.get("snapshot", {})) == SaveCodec.canonical(before), "R37 full canonical snapshot round-trip " + String(ending))
		t.check(session.restore(decoded.payload.snapshot).ok, "R37 restore decoded completed state")
		var replay: MireTypes.ActionResult = session.quests.complete(&"sq_01_a_smiths_hand", &"save/replay")
		t.check(replay.ok and replay.payload.get("replayed", false) and SaveCodec.canonical(before) == SaveCodec.canonical(session.snapshot()), "R38 reload cannot repay a completed reward")
		decoded.payload.snapshot.player.crowns = 0
		t.check(session.state.player.crowns == before.player.crowns, "R39 decoded payload cannot mutate the restored session by reference")
	session.new_game()

func _malformed() -> void:
	var original: Dictionary = session.snapshot()
	var encoded := SaveCodec.encode(original, &"manual_1", 100, db)
	t.check(encoded.ok and _decode(encoded.payload.text).ok, "R37 initial state has a valid versioned checksum envelope")
	var envelope: Dictionary = encoded.payload.envelope
	for field: String in ["schema_version", "game_version", "content_version", "timestamp", "slot", "checksum", "payload"]:
		for value: Variant in [null, [], {}, true, "invalid"]:
			var bad := envelope.duplicate(true)
			bad[field] = value
			t.check(not _decode(JSON.stringify(bad)).ok, "R38 reject malformed envelope " + field + "/" + str(value))
	var changed := envelope.duplicate(true)
	for value: Variant in [null, [], {}, true, 5]:
		var invalid_slot := envelope.duplicate(true)
		invalid_slot.slot.id = value
		t.check(not _decode(JSON.stringify(invalid_slot)).ok, "R38 invalid nested slot identity fails without a script error")
	changed.payload.player.crowns += 1
	t.check(_decode(JSON.stringify(changed)).code == &"checksum_mismatch", "R38 checksum detects changed payload bytes")
	changed = envelope.duplicate(true)
	changed.schema_version = 2
	t.check(_decode(JSON.stringify(changed)).code == &"unsupported_schema", "R38 future schema is rejected explicitly")
	changed = envelope.duplicate(true)
	changed.slot.chapter = "Wrong chapter"
	t.check(not _decode(JSON.stringify(changed)).ok, "R38 slot metadata must describe its snapshot")
	for field: String in SaveCodec.STATE_FIELDS:
		var missing := original.duplicate(true)
		missing.erase(field)
		t.check(not SaveCodec.encode(missing, &"manual_1", 100, db).ok, "R38 missing domain is rejected: " + field)
	for flag: String in original.flags:
		var missing := original.duplicate(true)
		missing.flags.erase(flag)
		t.check(not SaveCodec.encode(missing, &"manual_1", 100, db).ok, "R38 missing runtime flag is rejected: " + flag)
	for slot: String in ["shield", "armor"]:
		var missing := original.duplicate(true)
		missing.equipment.erase(slot)
		t.check(not SaveCodec.encode(missing, &"manual_1", 100, db).ok, "R38 optional empty equipment still requires its runtime slot key")
	for id: String in ["cart_coffer", "south_cart_cutpurse_01"]:
		for record: Dictionary in [{}, {"defeated": "yes"}, {"kind": "wrong"}]:
			var invalid := original.duplicate(true)
			invalid.world[id] = record
			t.check(not SaveCodec.encode(invalid, &"manual_1", 100, db).ok, "R38 known loot records cannot omit their typed kind")
	var invalid := original.duplicate(true)
	invalid.world.unknown_entity = {}
	t.check(not SaveCodec.encode(invalid, &"manual_1", 100, db).ok, "R38 unknown persistent entity is refused")
	invalid = original.duplicate(true)
	invalid.world.south_cart_cutpurse_01 = session.world_state.get_entity_state(&"south_cart_cutpurse_01")
	invalid.world.south_cart_cutpurse_01.health = 12
	t.check(not SaveCodec.encode(invalid, &"manual_1", 100, db).ok, "R37 transient hostile health cannot enter a save")
	invalid = original.duplicate(true)
	invalid.quests.mq_01_bread_and_iron.state = "COMPLETED"
	var forged := envelope.duplicate(true)
	forged.payload = invalid
	forged.checksum = SaveCodec.canonical(invalid).sha256_text()
	t.check(not _decode(JSON.stringify(forged)).ok, "R38 even a matching checksum cannot bypass quest semantics")
	invalid = original.duplicate(true)
	invalid.inventory[0].item_id = "unknown_sword"
	t.check(not SaveCodec.encode(invalid, &"manual_1", 100, db).ok, "R38 unknown item ownership fails")
	invalid = original.duplicate(true)
	invalid.player.crowns = -1
	t.check(not SaveCodec.encode(invalid, &"manual_1", 100, db).ok, "R38 negative currency fails")
	invalid = original.duplicate(true)
	invalid.player.scene_id = "interior_undercroft"
	t.check(not SaveCodec.encode(invalid, &"manual_1", 100, db).ok, "R38 save cannot bypass Ada's undercroft gate")
	invalid = original.duplicate(true)
	invalid.shop_stock.erase("oswin_pike")
	t.check(not SaveCodec.encode(invalid, &"manual_1", 100, db).ok, "R38 incomplete shop data fails")
	t.check(not _decode("{").ok and not _decode("[]").ok, "R38 truncated and non-object JSON fail safely")
	t.check(SaveCodec.canonical(session.snapshot()) == SaveCodec.canonical(original), "R39 every malformed save leaves current session unchanged")

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _file_failures() -> void:
	var base: String = t.test_save_directory.path_join("failure_cases")
	var old := SaveCodec.encode(session.snapshot(), &"manual_1", 100, db)
	var newer := SaveCodec.encode(session.snapshot(), &"manual_1", 200, db)
	var latest := SaveCodec.encode(session.snapshot(), &"manual_1", 300, db)
	var stages: Array[StringName] = [&"directory", &"temporary_open", &"temporary_write", &"temporary_flush", &"temporary_readback", &"temporary_validate", &"existing_read", &"backup_open", &"backup_write", &"backup_flush", &"backup_readback", &"backup_validate", &"backup_replace", &"replace"]
	for stage: StringName in stages:
		var path := base.path_join(String(stage) + ".json")
		t.check(SaveCodec.write_file(path, old.payload.text, _decode).ok and SaveCodec.write_file(path, newer.payload.text, _decode).ok, "R38 prepare real primary and backup for " + String(stage))
		var result := SaveCodec.write_file(path, latest.payload.text, _decode, func(at: StringName) -> bool: return at == stage)
		t.check(not result.ok and result.payload.stage == String(stage), "R38 report injected I/O failure " + String(stage))
		t.check(FileAccess.get_file_as_string(path) == newer.payload.text and SaveCodec.read_file(path, _decode).ok, "R38 preserve valid primary on " + String(stage))
		t.check(SaveCodec.read_file(path + ".bak", _decode).ok, "R38 preserve a valid backup on " + String(stage))
		t.check(not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".bak.tmp"), "R38 failed write cleans only temporary files")
		if not String(stage).begins_with("backup") and stage != &"existing_read":
			var first_path := base.path_join("first_" + String(stage) + ".json")
			result = SaveCodec.write_file(first_path, latest.payload.text, _decode, func(at: StringName) -> bool: return at == stage)
			t.check(not result.ok and not FileAccess.file_exists(first_path), "R38 failed first save is clearly reported for " + String(stage))
	var blocker := base.path_join("file_is_not_directory")
	_write(blocker, "obstruction")
	t.check(not SaveCodec.write_file(blocker.path_join("save.json"), latest.payload.text, _decode).ok, "R38 actual filesystem directory failure is reported")
	var damaged := base.path_join("damaged.json")
	_write(damaged, "broken")
	_write(damaged + ".bak", old.payload.text)
	t.check(SaveCodec.write_file(damaged, newer.payload.text, _decode).ok and FileAccess.get_file_as_string(damaged + ".bak") == old.payload.text, "R38 writing over corrupt primary preserves the existing valid backup")
	if OS.get_name() in ["macOS", "Linux"]:
		var unreadable := base.path_join("unreadable_primary.json")
		_write(unreadable, old.payload.text)
		var output: Array = []
		t.check(OS.execute("/bin/chmod", ["000", unreadable], output) == 0, "R38 make only an isolated fixture file unreadable")
		var inspected := SaveCodec.read_file(unreadable, _decode)
		t.check(not inspected.ok and inspected.code == &"read_failed", "R38 actual unreadable primary reports read failure")
		var attempted := SaveCodec.write_file(unreadable, newer.payload.text, _decode)
		OS.execute("/bin/chmod", ["600", unreadable], output)
		t.check(not attempted.ok and FileAccess.get_file_as_string(unreadable) == old.payload.text, "R38 an unreadable primary cannot be replaced without preserving it")

func _slot_inspection() -> void:
	t.check(saves.list_slots().size() == 4 and not saves.continue_slot().ok, "R37 four empty slots do not crash Continue")
	for index: int in 3:
		var slot: StringName = SaveCodec.SLOTS[index + 1]
		var encoded := SaveCodec.encode(session.snapshot(), slot, 100 + index, db)
		_write(saves.slot_path(slot), encoded.payload.text)
	t.check(saves.continue_slot().payload.slot_id == "manual_3", "R40 Continue picks newest valid saved timestamp")
	var newer_path: String = saves.slot_path(&"manual_3")
	_write(newer_path, "corrupt newer primary")
	var backup := SaveCodec.encode(session.snapshot(), &"manual_3", 103, db)
	_write(saves.slot_path(&"manual_3", true), backup.payload.text)
	var bytes := FileAccess.get_file_as_string(newer_path)
	var offered: MireTypes.ActionResult = saves.inspect_slot(&"manual_3")
	t.check(not offered.ok and offered.code == &"backup_available" and offered.payload.backup_timestamp == 103, "R38 corrupt primary offers explicit identified backup recovery")
	t.check(saves.inspect_slot(&"manual_3", true).ok, "R38 explicit backup selection reads validated backup")
	var selection: MireTypes.ActionResult = saves.continue_slot()
	t.check(selection.ok and selection.payload.slot_id == "manual_2" and "manual_3" in selection.payload.skipped, "R40 Continue skips invalid primary with notice and does not silently select backup")
	t.check(FileAccess.get_file_as_string(newer_path) == bytes, "R38 listing and recovery inspection never rewrite damaged primary")
	_write(saves.slot_path(&"manual_3", true), "also broken")
	t.check(not saves.inspect_slot(&"manual_3").ok and saves.inspect_slot(&"manual_3").code != &"backup_available", "R38 two damaged copies return a useful failure")
	t.check(not saves.inspect_slot(&"../outside").ok and saves.slot_path(&"../outside").is_empty(), "R38 slot identities cannot select arbitrary paths")

func _settings() -> void:
	var defaults: Dictionary = saves.DEFAULT_SETTINGS.duplicate(true)
	for field: String in defaults:
		for value: Variant in [null, true, [], {}, "invalid", -1]:
			if typeof(value) == typeof(defaults[field]):
				continue
			var malformed := defaults.duplicate(true)
			malformed[field] = value
			t.check(not SettingsValidation.validate(malformed).ok, "R37 reject malformed settings field: " + field)
	for value: Variant in [null, true, [], {}, "invalid", -1]:
		t.check(not saves._decode_settings(JSON.stringify({"schema_version": value, "settings": defaults})).ok, "R38 malformed settings envelope schema fails safely")
	t.check(SettingsValidation.validate(defaults).ok and saves.save_settings(defaults).ok, "R37 separate default settings persist")
	var before := FileAccess.get_file_as_string(saves.settings_path())
	for row: Array in [["fov", 96], ["fov", 59], ["mouse_sensitivity", 0], ["music_volume", 1.1], ["text_scale", 2], ["fullscreen", "yes"], ["bindings", []], ["dismissed_hints", ["same", "same"]]]:
		var bad := defaults.duplicate(true)
		bad[row[0]] = row[1]
		t.check(not saves.save_settings(bad).ok and FileAccess.get_file_as_string(saves.settings_path()) == before, "R37 invalid settings do not replace disk values: " + String(row[0]))
	t.check(saves.rebind(&"interact", {"type": "key", "code": KEY_W}).code == &"binding_conflict", "R08 a conflicting remap requests swap or cancel")
	t.check(saves.rebind(&"interact", {"type": "key", "code": KEY_W}, true).ok, "R08 explicit swap commits both input assignments")
	t.check(InputMap.action_get_events(&"interact")[0].physical_keycode == KEY_W and InputMap.action_get_events(&"move_forward")[0].physical_keycode == KEY_E, "R08 remap reaches the real InputMap")
	t.check(not saves.rebind(&"attack_light", {"type": "key", "code": KEY_ESCAPE}, true).ok, "R08 Escape cannot be stolen by gameplay")
	t.check(saves.rebind(&"pause", {"type": "key", "code": KEY_P}).ok, "R08 pause itself may be remapped while mandatory Escape is independently retained")
	t.check(saves.rebind(&"quick_heal", {"type": "mouse", "code": MOUSE_BUTTON_MIDDLE}).ok, "R08 mouse buttons may be bound to digital actions")
	var settings_before: Dictionary = saves.settings.duplicate(true)
	session.new_game()
	t.check(saves.settings == settings_before and saves.load_settings().ok and saves.settings == settings_before, "R40 New Game retains separately persisted settings")
	saves.write_fault = func(stage: StringName) -> bool: return stage == &"replace"
	var changed: Dictionary = saves.settings.duplicate(true)
	changed.text_scale = 1.5
	t.check(not saves.save_settings(changed).ok and saves.settings == settings_before, "R38 settings write failure preserves active and disk settings")
	saves.write_fault = Callable()
	_write(saves.settings_path(), "{bad settings")
	t.check(not saves.load_settings().ok and saves.settings == settings_before, "R38 damaged settings are not silently overwritten or applied")
	t.check(saves.load_settings(true).ok, "R38 explicit settings backup recovery is available")
	t.check(saves.save_settings(defaults).ok, "R37 restore default bindings for subsequent isolated tests")

func _held_inputs() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await t.physics_frame
	t.check(Input.is_physical_key_pressed(KEY_W) and Input.is_action_pressed(&"move_forward"), "R08 actual held key activates movement before settings persistence")
	for change: Dictionary in [{"dismissed_hints": ["movement"]}, {"fov": 85.0}, {"master_volume": 0.5}, {"render_mode": "native"}, {"bindings": {"move_forward": {"type": "key", "code": KEY_W}}}]:
		var candidate: Dictionary = saves.settings.duplicate(true)
		candidate.merge(change, true)
		t.check(saves.save_settings(candidate).ok and Input.is_action_pressed(&"move_forward"), "R08 unrelated settings or equivalent bindings preserve held movement: " + str(change.keys()))
	t.check(saves.rebind(&"quick_heal", {"type": "key", "code": KEY_H}).ok and Input.is_action_pressed(&"move_forward"), "R08 changing another action preserves the held movement action")
	var released: InputEventKey = key.duplicate()
	released.pressed = false
	Input.parse_input_event(released)
	Input.flush_buffered_events()
	await t.physics_frame
	t.check(not Input.is_action_pressed(&"move_forward") and not Input.is_physical_key_pressed(KEY_W), "R08 the normal release still clears preserved movement")
	t.check(saves.save_settings(saves.DEFAULT_SETTINGS.duplicate(true)).ok, "R37 held-input fixture restores default settings")
