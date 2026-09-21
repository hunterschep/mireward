extends Node

var items: Dictionary = {}
var enemies: Dictionary = {}
var quests: Dictionary = {}
var dialogues: Dictionary = {}
var map: Dictionary = {}
var shops: Dictionary = {}
var containers: Dictionary = {}
var errors: PackedStringArray = []

func _ready() -> void:
	reload_content()

func reload_content() -> void:
	errors.clear()
	items.clear()
	enemies.clear()
	quests.clear()
	dialogues.clear()
	map.clear()
	shops.clear()
	containers.clear()
	_load_registry("res://data/items/items.json", items, &"item")
	_load_registry("res://data/enemies/enemies.json", enemies, &"enemy")
	_load_registry("res://data/quests/quests.json", quests, &"quest")
	_load_registry("res://data/dialogue/dialogues.json", dialogues, &"dialogue")
	var map_value: Variant = read_json("res://data/world/map.json")
	var shop_value: Variant = read_json("res://data/loot/shops.json")
	if map_value is Dictionary:
		var map_errors: PackedStringArray = ContentValidation.world(map_value)
		if map_errors.is_empty():
			map = map_value
		else:
			errors.append_array(map_errors)
	else:
		errors.append("World registry must be a dictionary.")
	if shop_value is Dictionary:
		shops = shop_value
	else:
		errors.append("Shop registry must be a dictionary.")
	var container_rows: Variant = read_json("res://data/loot/containers.json")
	if container_rows is Array:
		var container_errors := ContentValidation.container_registry(container_rows, items, map.get("spawns", []))
		if container_errors.is_empty():
			for row: Dictionary in container_rows:
				containers[String(row.id)] = row.duplicate(true)
		else:
			errors.append_array(container_errors)
	else:
		errors.append("Container registry must be an array.")

func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("Missing registry: %s" % path)
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("Invalid JSON %s:%s: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data

func _load_registry(path: String, target: Dictionary, kind: StringName) -> void:
	var value: Variant = read_json(path)
	if not value is Array:
		errors.append("Registry must be an array: %s" % path)
		return
	for raw: Variant in value:
		var row_errors: PackedStringArray = ContentValidation.definition(raw, String(kind))
		if not row_errors.is_empty():
			errors.append_array(row_errors)
			continue
		var id := StringName(raw.id)
		if target.has(id):
			errors.append("Duplicate %s ID: %s" % [kind, id])
			continue
		match kind:
			&"item": target[id] = MireTypes.ItemDef.new(raw)
			&"enemy": target[id] = MireTypes.EnemyDef.new(raw)
			&"quest": target[id] = MireTypes.QuestDef.new(raw)
			&"dialogue": target[id] = MireTypes.DialogueDef.new(raw)

func get_item(id: StringName) -> MireTypes.ItemDef:
	if not items.has(id):
		push_error("Unknown item ID: %s" % id)
	return items.get(id)

func get_enemy(id: StringName) -> MireTypes.EnemyDef:
	if not enemies.has(id):
		push_error("Unknown enemy ID: %s" % id)
	return enemies.get(id)

func get_quest(id: StringName) -> MireTypes.QuestDef:
	if not quests.has(id):
		push_error("Unknown quest ID: %s" % id)
	return quests.get(id)

func get_dialogue(id: StringName) -> MireTypes.DialogueDef:
	if not dialogues.has(id):
		push_error("Unknown dialogue ID: %s" % id)
	return dialogues.get(id)
