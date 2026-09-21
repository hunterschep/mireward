class_name MireTypes
extends RefCounted

const WORLD := 1
const PLAYER := 2
const HOSTILE := 4
const NEUTRAL := 8
const INTERACTABLE := 16
const HURTBOX := 32
const TRIGGER := 64
const MODES := [&"gameplay", &"title", &"pause", &"inventory", &"journal", &"map", &"dialogue", &"shop", &"settings", &"death", &"epilogue", &"confirmation", &"readable", &"travel", &"save", &"load"]

class ActionResult extends RefCounted:
	var ok: bool
	var code: StringName
	var message_key: StringName
	var payload: Dictionary
	var events: Array[Dictionary] = []
	func _init(success: bool = false, result_code: StringName = &"unsupported", message: StringName = &"Action is not available.", data: Dictionary = {}) -> void:
		ok = success
		code = result_code
		message_key = message
		payload = data
	func event(event_name: StringName, args: Array = []) -> ActionResult:
		events.append({"name": event_name, "args": args})
		return self

class ItemDef extends RefCounted:
	var id: StringName
	var name_key: String
	var description_key: String
	var category: StringName
	var icon_path: String
	var base_price: int
	var max_stack: int
	var data: Dictionary
	func _init(raw: Dictionary) -> void:
		data = raw.duplicate(true)
		id = StringName(raw.id)
		name_key = raw.name_key
		description_key = raw.description_key
		category = StringName(raw.category)
		icon_path = raw.icon_path
		base_price = int(raw.base_price)
		max_stack = int(raw.max_stack)

class EnemyDef extends RefCounted:
	var id: StringName
	var max_health: int
	var armor: float
	var data: Dictionary
	func _init(raw: Dictionary) -> void:
		data = raw.duplicate(true)
		id = StringName(raw.id)
		max_health = int(raw.max_health)
		armor = float(raw.armor)

class QuestDef extends RefCounted:
	var id: StringName
	var data: Dictionary
	func _init(raw: Dictionary) -> void:
		id = StringName(raw.id)
		data = raw.duplicate(true)

class DialogueDef extends RefCounted:
	var id: StringName
	var npc_id: StringName
	var nodes: Array
	var data: Dictionary
	func _init(raw: Dictionary) -> void:
		data = raw.duplicate(true)
		id = StringName(raw.id)
		npc_id = StringName(raw.npc_id)
		nodes = raw.get("nodes", [])

class InteractionOffer extends RefCounted:
	var entity_id: StringName
	var prompt_key: String
	var allowed: bool
	var reason_key: String
	var action_id: StringName
	func _init(entity: StringName = &"", prompt: String = "", can_use: bool = true, reason: String = "", action: StringName = &"interact") -> void:
		entity_id = entity
		prompt_key = prompt
		allowed = can_use
		reason_key = reason
		action_id = action

class DamageRequest extends RefCounted:
	var attacker_id: StringName
	var attack_sequence: int
	var victim_id: StringName
	var raw_damage: float
	var attack_kind: StringName
	var origin: Vector3
	var source_faction: StringName
	func _init(attacker: StringName = &"", sequence: int = 0, victim: StringName = &"", damage: float = 0.0, kind: StringName = &"light", from: Vector3 = Vector3.ZERO, faction: StringName = &"player") -> void:
		attacker_id = attacker
		attack_sequence = sequence
		victim_id = victim
		raw_damage = damage
		attack_kind = kind
		origin = from
		source_faction = faction

class DamageResult extends RefCounted:
	var outcome: StringName = &"ignored"
	var health_damage: int = 0
	var stamina_damage: int = 0
	var stagger_seconds: float = 0.0

class ItemStack extends RefCounted:
	var stack_id: StringName
	var item_id: StringName
	var quantity: int
	func _init(stack: StringName, item: StringName, count: int) -> void:
		stack_id = stack
		item_id = item
		quantity = count

static func success(payload: Dictionary = {}, message: StringName = &"") -> ActionResult:
	return ActionResult.new(true, &"ok", message, payload)

static func failure(code: StringName, message: StringName) -> ActionResult:
	return ActionResult.new(false, code, message)
