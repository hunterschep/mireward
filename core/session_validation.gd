class_name SessionValidation
extends RefCounted

const QUEST_STATES := ["LOCKED", "AVAILABLE", "ACTIVE", "READY", "COMPLETED"]
const CHOICES := {"wren_terms": ["unset", "amnesty", "restitution"], "medicine_recipient": ["unset", "camp", "village"], "ending": ["none", "charter", "warden", "free_road"]}

static func validate(state: Dictionary, db: Node) -> MireTypes.ActionResult:
	if not json_safe(state):
		return invalid("Session contains non-JSON values, nonfinite numbers, or excessive nesting.")
	for key: String in ["player", "equipment", "key_items", "evidence", "quests", "world", "choices", "transactions", "pending_delivery", "shop_stock", "flags"]:
		if not state.get(key) is Dictionary:
			return invalid("Missing or invalid section: " + key)
	if not state.get("inventory") is Array or not state.get("discoveries") is Array:
		return invalid("Inventory and discoveries must be lists.")
	if state.inventory.size() > 16:
		return invalid("Inventory exceeds sixteen slots.")
	if not whole(state.get("next_stack")) or state.next_stack < 1:
		return invalid("Invalid next stack identity counter.")
	var player: Dictionary = state.player
	if not whole(player.get("crowns")) or player.crowns < 0:
		return invalid("Crowns must be a nonnegative integer.")
	for resource: String in ["health", "stamina"]:
		var amount: Variant = player.get(resource)
		if not number(amount) or amount < 0 or amount > 100:
			return invalid("Invalid player " + resource)
	if not player.get("scene_id") is String or not db.map.get("scenes", {}).has(player.scene_id):
		return invalid("Unknown player scene.")
	if not player.get("rest_anchor") is String or not db.map.get("rest_points", {}).has(player.rest_anchor):
		return invalid("Unknown rest anchor.")
	if not vector(player.get("position")) or not number(player.get("yaw")):
		return invalid("Invalid player transform.")
	var owned: Dictionary = {}
	var weapons: int = 0
	for stack: Variant in state.inventory:
		if not stack is Dictionary or not identifier(stack.get("stack_id")) or owned.has(stack.stack_id):
			return invalid("Invalid or duplicated stack identity.")
		if not identifier(stack.get("item_id")) or not db.items.has(StringName(stack.item_id)):
			return invalid("Unknown inventory item.")
		var definition: MireTypes.ItemDef = db.items[StringName(stack.item_id)]
		if definition.category in [&"quest", &"evidence"] or not whole(stack.get("quantity")) or stack.quantity < 1 or stack.quantity > definition.max_stack:
			return invalid("Invalid stack quantity or category.")
		owned[stack.stack_id] = definition
		if definition.category == &"weapon":
			weapons += 1
		if stack.stack_id.begins_with("stack_") and stack.stack_id.trim_prefix("stack_").is_valid_int() and int(stack.stack_id.trim_prefix("stack_")) >= state.next_stack:
			return invalid("Next stack identity collides with existing inventory.")
	if weapons < 1:
		return invalid("At least one melee weapon must be owned.")
	for slot: String in state.equipment:
		if slot not in ["weapon", "shield", "armor"]:
			return invalid("Unknown equipment slot: " + slot)
	for slot: String in ["weapon", "shield", "armor"]:
		if not state.equipment.get(slot, "") is String:
			return invalid("Invalid equipment stack identity.")
		var stack_id: String = state.equipment.get(slot, "")
		if stack_id.is_empty() and slot != "weapon":
			continue
		if not owned.has(stack_id) or owned[stack_id].category != StringName(slot):
			return invalid("Equipment does not belong to its slot: " + slot)
	for item_id: String in state.key_items:
		if not db.items.has(StringName(item_id)):
			return invalid("Unknown key item.")
		var definition: MireTypes.ItemDef = db.items[StringName(item_id)]
		if definition.category not in [&"quest", &"evidence"] or not whole(state.key_items[item_id]) or state.key_items[item_id] < 0 or state.key_items[item_id] > definition.max_stack:
			return invalid("Invalid key-item quantity or category.")
	for choice: String in CHOICES:
		if state.choices.get(choice) not in CHOICES[choice]:
			return invalid("Invalid choice: " + choice)
	for quest_id: String in state.quests:
		var record: Variant = state.quests[quest_id]
		if not db.quests.has(StringName(quest_id)) or not record is Dictionary or record.get("state") not in QUEST_STATES or not record.get("objectives") is Dictionary:
			return invalid("Invalid quest record: " + quest_id)
	for quest_id: StringName in db.quests:
		if not state.quests.has(String(quest_id)):
			return invalid("Missing quest record: " + String(quest_id))
	for section: String in ["evidence", "flags"]:
		for id: String in state[section]:
			if id.is_empty() or not state[section][id] is bool:
				return invalid("Invalid flag in " + section)
	for id: String in state.world:
		if id.is_empty() or not state.world[id] is Dictionary:
			return invalid("Invalid persistent world record.")
	var landmarks: Dictionary = {}
	for landmark: Dictionary in db.map.get("landmarks", []):
		landmarks[landmark.id] = true
	var discovered: Dictionary = {}
	for id: Variant in state.discoveries:
		if not identifier(id) or not landmarks.has(id) or discovered.has(id):
			return invalid("Unknown or repeated discovered landmark.")
		discovered[id] = true
	for id: String in state.transactions:
		if id.is_empty() or not receipt(state.transactions[id]):
			return invalid("Invalid transaction receipt: " + id)
	for id: String in state.pending_delivery:
		var delivery: Variant = state.pending_delivery[id]
		if id.is_empty() or not delivery is Dictionary or not identifier(delivery.get("item_id")) or not db.items.has(StringName(delivery.item_id)) or not whole(delivery.get("quantity")) or delivery.quantity < 1:
			return invalid("Invalid pending delivery: " + id)
	for shop_id: String in state.shop_stock:
		if not db.shops.has(shop_id) or not state.shop_stock[shop_id] is Dictionary:
			return invalid("Unknown or invalid shop: " + shop_id)
		for item_id: String in state.shop_stock[shop_id]:
			var quantity: Variant = state.shop_stock[shop_id][item_id]
			if not db.shops[shop_id].has(item_id) or not whole(quantity) or (db.shops[shop_id][item_id] == -1 and quantity != -1) or (db.shops[shop_id][item_id] >= 0 and (quantity < 0 or quantity > db.shops[shop_id][item_id])):
				return invalid("Invalid shop stock: " + item_id)
	return MireTypes.success()

static func receipt(value: Variant) -> bool:
	return value is Dictionary and identifier(value.get("code")) and value.get("message_key") is String and value.get("payload") is Dictionary and json_safe(value)

static func json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	if value == null or value is bool or value is String:
		return true
	if number(value):
		return is_finite(float(value))
	if value is Array:
		for entry: Variant in value:
			if not json_safe(entry, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not json_safe(value[key], depth + 1):
				return false
		return true
	return false

static func identifier(value: Variant) -> bool:
	return value is String and not value.is_empty()

static func vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and number(value[0]) and number(value[1]) and number(value[2]) and json_safe(value)

static func number(value: Variant) -> bool:
	return value is int or value is float

static func whole(value: Variant) -> bool:
	return number(value) and is_finite(float(value)) and float(value) == floor(float(value))

static func invalid(message: String) -> MireTypes.ActionResult:
	return MireTypes.failure(&"invalid_state", StringName(message))
