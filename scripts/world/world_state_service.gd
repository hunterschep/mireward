class_name WorldStateService
extends RefCounted
## Persistent world state and deterministic loot. Read methods never materialize state.

const CONTAINER_PATH := "res://data/loot/containers.json"
const RESERVED_FIELDS := ["kind", "remaining", "crowns_remaining", "defeated", "archetype"]
var session: Node
var db: Node
var inventory: InventoryService
var errors: PackedStringArray = []
var _definitions: Dictionary = {}
var _spawns: Dictionary = {}

func _init(owner: Node) -> void:
	session = owner
	db = owner.get_node("/root/ContentDB")
	inventory = owner.inventory
	for spawn: Dictionary in db.map.get("spawns", []):
		_spawns[String(spawn.id)] = spawn.duplicate(true)
	for row: Dictionary in db.containers.values():
		var result := define_loot(StringName(row.id), row.items, int(row.crowns))
		if not result.ok:
			errors.append(String(result.message_key))
		else:
			_definitions[String(row.id)]["label"] = String(row.label)

## Register authored ordinary loot before using its stable entity ID. No save mutation.
func define_loot(entity_id: StringName, items: Dictionary, crowns: int = 0) -> MireTypes.ActionResult:
	var id := String(entity_id)
	if id.is_empty() or _spawns.has(id) or _definitions.has(id):
		return MireTypes.failure(&"invalid_source", &"Loot sources need a unique stable identity.")
	if session.state.world.has(id) and session.state.world[id].get("kind") != "container":
		return MireTypes.failure(&"invalid_source", &"That identity belongs to a different world entity.")
	if not SessionValidation.json_safe(items) or crowns < 0:
		return MireTypes.failure(&"invalid_loot", &"Loot counts must be nonnegative whole numbers.")
	for item_id: String in items:
		var definition: MireTypes.ItemDef = db.items.get(StringName(item_id))
		if definition == null or not SessionValidation.whole(items[item_id]) or items[item_id] <= 0:
			return MireTypes.failure(&"invalid_loot", &"The container contains an unknown item or invalid quantity.")
		if definition.category in InventoryService.KEYS and items[item_id] > definition.max_stack:
			return MireTypes.failure(&"invalid_loot", &"The container exceeds the authored key-item count.")
	var quantities: Dictionary = {}
	for item_id: String in items:
		quantities[item_id] = int(items[item_id])
	_definitions[id] = {"id": id, "label": id, "items": quantities, "crowns": crowns}
	return MireTypes.success({"entity_id": id})

func get_entity_state(entity_id: StringName) -> Dictionary:
	return _record(session.state, String(entity_id))

func read_loot(entity_id: StringName) -> MireTypes.ActionResult:
	var valid := _loot_available(session.state, String(entity_id))
	if not valid.ok:
		return valid
	var record := _record(session.state, String(entity_id))
	return MireTypes.success({"entity_id": String(entity_id), "items": record.remaining.duplicate(true), "crowns": int(record.crowns_remaining), "opened": bool(record.opened), "empty": record.remaining.is_empty() and int(record.crowns_remaining) == 0})

## A selected quantity may be partially collected; zero fitting quantity fails intact.
func take_loot(entity_id: StringName, item_id: StringName, quantity: int, transaction_id: StringName) -> MireTypes.ActionResult:
	return session.transactions.run(transaction_id, func(candidate: Dictionary) -> MireTypes.ActionResult:
		var id := String(entity_id)
		var available := _loot_available(candidate, id)
		if not available.ok:
			return available
		if quantity <= 0:
			return MireTypes.failure(&"invalid_quantity", &"Choose a positive pickup quantity.")
		var record := _record(candidate, id)
		var item := String(item_id)
		var remaining: int = int(record.remaining.get(item, 0))
		if quantity > remaining:
			return MireTypes.failure(&"not_available", &"That quantity is no longer in the container.")
		var result := inventory.stage_add(candidate, item_id, quantity, entity_id, true)
		if not result.ok:
			return result
		var left: int = remaining - int(result.payload.added)
		if left == 0:
			record.remaining.erase(item)
		else:
			record.remaining[item] = left
		record.opened = true
		candidate.world[id] = record
		result.payload["entity_id"] = id
		result.payload["container_remaining"] = left
		return result
	)

func take_crowns(entity_id: StringName, transaction_id: StringName) -> MireTypes.ActionResult:
	return session.transactions.run(transaction_id, func(candidate: Dictionary) -> MireTypes.ActionResult:
		var id := String(entity_id)
		var available := _loot_available(candidate, id)
		if not available.ok:
			return available
		var record := _record(candidate, id)
		var crowns: int = int(record.crowns_remaining)
		if crowns <= 0:
			return MireTypes.failure(&"empty", &"There are no crowns left to collect.")
		candidate.player.crowns = int(candidate.player.crowns) + crowns
		record.crowns_remaining = 0
		record.opened = true
		candidate.world[id] = record
		return MireTypes.success({"entity_id": id, "crowns": crowns}).event(&"currency_changed")
	)

func mark_defeated(entity_id: StringName) -> MireTypes.ActionResult:
	if not _spawns.has(String(entity_id)):
		return MireTypes.failure(&"unknown_entity", &"That hostile spawn is not authored.")
	return session.transactions.run(StringName("world/defeat/" + String(entity_id)), func(candidate: Dictionary) -> MireTypes.ActionResult:
		var id := String(entity_id)
		var record := _record(candidate, id)
		if bool(record.defeated):
			return MireTypes.success({"entity_id": id, "already_defeated": true})
		record.defeated = true
		candidate.world[id] = record
		return MireTypes.success({"entity_id": id}).event(&"entity_defeated", [entity_id])
	)

## Generic story state merges cannot refill loot, change identity, or resurrect enemies.
func apply_transaction(changes: Dictionary, transaction_id: StringName) -> MireTypes.ActionResult:
	return session.transactions.run(transaction_id, func(candidate: Dictionary) -> MireTypes.ActionResult:
		if changes.is_empty() or not SessionValidation.json_safe(changes):
			return MireTypes.failure(&"invalid_changes", &"World changes must contain saved entity values.")
		for entity_id: String in changes:
			if entity_id.is_empty() or not changes[entity_id] is Dictionary:
				return MireTypes.failure(&"invalid_changes", &"Each world change needs a stable entity and record.")
			var patch: Dictionary = changes[entity_id]
			var record := _record(candidate, entity_id)
			for key: String in patch:
				if key in RESERVED_FIELDS:
					return MireTypes.failure(&"protected_state", &"Defeat and loot must use their dedicated actions.")
				if key in ["opened", "disabled"] and not patch[key] is bool:
					return MireTypes.failure(&"invalid_changes", &"Opened and disabled flags must be true or false.")
				if key == "opened" and record.get("opened", false) and not patch[key]:
					return MireTypes.failure(&"protected_state", &"An opened container cannot be reset.")
			record.merge(patch, true)
			candidate.world[entity_id] = record
		return MireTypes.success({"entity_ids": changes.keys()})
	)

func _loot_available(candidate: Dictionary, id: String) -> MireTypes.ActionResult:
	if not _definitions.has(id) and not _spawns.has(id):
		return MireTypes.failure(&"unknown_entity", &"That loot source is not authored.")
	var record := _record(candidate, id)
	if record.get("kind") == "corpse" and not bool(record.defeated):
		return MireTypes.failure(&"not_defeated", &"This enemy has not been defeated.")
	return MireTypes.success()

func _record(candidate: Dictionary, id: String) -> Dictionary:
	var result: Dictionary = {}
	if _definitions.has(id):
		var definition: Dictionary = _definitions[id]
		result = {"kind": "container", "opened": false, "remaining": definition.items.duplicate(true), "crowns_remaining": int(definition.crowns)}
	elif _spawns.has(id):
		var archetype: String = _spawns[id].archetype
		var enemy: MireTypes.EnemyDef = db.enemies.get(StringName(archetype))
		result = {"kind": "corpse", "opened": false, "remaining": {}, "crowns_remaining": int(enemy.data.loot_crowns), "defeated": false, "disabled": false, "archetype": archetype}
	result.merge(candidate.world.get(id, {}).duplicate(true), true)
	if result.get("kind") in ["container", "corpse"]:
		result.crowns_remaining = int(result.crowns_remaining)
		for item_id: String in result.remaining:
			result.remaining[item_id] = int(result.remaining[item_id])
	return result
