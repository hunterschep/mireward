class_name InventoryService
extends RefCounted
## Inventory changes stage into Transactions; constructors never grant items.

const SLOT_LIMIT := 16
const EQUIPMENT := [&"weapon", &"shield", &"armor"]
const KEYS := [&"quest", &"evidence"]
var session: Node
var db: Node
var consume_handler: Callable
var _action_sequence: int = 0

func _init(owner: Node) -> void:
	session = owner
	db = owner.get_node("/root/ContentDB")

func try_add(item_id: StringName, quantity: int, source_id: StringName) -> MireTypes.ActionResult:
	if source_id.is_empty():
		return MireTypes.failure(&"invalid_source", &"The pickup needs a stable source.")
	return session.transactions.run(StringName("inventory/add/" + String(source_id)), func(candidate: Dictionary) -> MireTypes.ActionResult:
		return stage_add(candidate, item_id, quantity, source_id)
	)

func try_equip(stack_id: StringName) -> MireTypes.ActionResult:
	return session.transactions.run(_next_action("equip"), func(candidate: Dictionary) -> MireTypes.ActionResult:
		if session.action_locked or session.travelling:
			return MireTypes.failure(&"action_locked", &"Finish your action before changing equipment.")
		var stack := find_stack(stack_id, candidate)
		if stack.is_empty():
			return MireTypes.failure(&"not_owned", &"That item is no longer in your inventory.")
		var definition: MireTypes.ItemDef = db.items.get(StringName(stack.item_id))
		if definition.category not in EQUIPMENT:
			return MireTypes.failure(&"not_equipment", &"This item cannot be equipped.")
		var slot := String(definition.category)
		if candidate.equipment[slot] == String(stack_id):
			return MireTypes.success({"slot": slot, "stack_id": String(stack_id), "already_equipped": true})
		candidate.equipment[slot] = String(stack_id)
		return MireTypes.success({"slot": slot, "stack_id": String(stack_id)}).event(&"equipment_changed")
	)

func try_unequip(slot: StringName) -> MireTypes.ActionResult:
	return session.transactions.run(_next_action("unequip"), func(candidate: Dictionary) -> MireTypes.ActionResult:
		if session.action_locked or session.travelling:
			return MireTypes.failure(&"action_locked", &"Finish your action before changing equipment.")
		if slot == &"weapon":
			return MireTypes.failure(&"weapon_required", &"Equip another weapon before putting this one away.")
		if slot not in [&"shield", &"armor"]:
			return MireTypes.failure(&"invalid_slot", &"Choose a shield or armor slot.")
		var old: String = candidate.equipment[String(slot)]
		candidate.equipment[String(slot)] = ""
		var result := MireTypes.success({"slot": String(slot), "stack_id": old})
		if not old.is_empty():
			result.event(&"equipment_changed")
		return result
	)

func try_consume(stack_id: StringName) -> MireTypes.ActionResult:
	var stack := find_stack(stack_id)
	if stack.is_empty():
		return MireTypes.failure(&"not_owned", &"That item is no longer in your inventory.")
	var definition: MireTypes.ItemDef = db.items[StringName(stack.item_id)]
	if definition.category != &"consumable":
		return MireTypes.failure(&"not_consumable", &"This item cannot be consumed.")
	if not consume_handler.is_valid():
		return MireTypes.failure(&"unsupported", &"Timed item use is not available yet.")
	if consume_handler.get_argument_count() != 1:
		return MireTypes.failure(&"invalid_handler", &"Item use could not be started.")
	var result: Variant = consume_handler.call(stack_id)
	if not result is MireTypes.ActionResult:
		return MireTypes.failure(&"invalid_handler", &"Item use could not be started.")
	return result

func claim_pending(delivery_id: StringName) -> MireTypes.ActionResult:
	if delivery_id.is_empty():
		return MireTypes.failure(&"invalid_delivery", &"Choose an unclaimed reward.")
	return session.transactions.run(StringName("inventory/claim/" + String(delivery_id)), func(candidate: Dictionary) -> MireTypes.ActionResult:
		var id := String(delivery_id)
		if not candidate.pending_delivery.has(id):
			return MireTypes.failure(&"not_pending", &"That reward is not awaiting collection.")
		var delivery: Dictionary = candidate.pending_delivery[id]
		var result := stage_add(candidate, StringName(delivery.item_id), int(delivery.quantity))
		if result.ok:
			candidate.pending_delivery.erase(id)
			result.payload["delivery_id"] = id
		return result
	)

func find_stack(stack_id: StringName, candidate: Dictionary = {}) -> Dictionary:
	var state: Dictionary = session.state if candidate.is_empty() else candidate
	for stack: Dictionary in state.inventory:
		if stack.stack_id == String(stack_id):
			return stack.duplicate(true)
	return {}

func view() -> Dictionary:
	return {"slots_used": session.state.inventory.size(), "slots_max": SLOT_LIMIT, "stacks": session.state.inventory.duplicate(true), "equipment": session.state.equipment.duplicate(true), "key_items": session.state.key_items.duplicate(true), "pending_delivery": session.state.pending_delivery.duplicate(true)}

func preview_add(item_id: StringName, quantity: int, candidate: Dictionary = {}) -> MireTypes.ActionResult:
	if not db.items.has(item_id):
		return MireTypes.failure(&"unknown_item", &"That item does not exist.")
	if quantity <= 0:
		return MireTypes.failure(&"invalid_quantity", &"Choose a positive item quantity.")
	var state: Dictionary = session.state if candidate.is_empty() else candidate
	var definition: MireTypes.ItemDef = db.items[item_id]
	var capacity: int = 0
	if definition.category in KEYS:
		capacity = maxi(0, definition.max_stack - int(state.key_items.get(String(item_id), 0)))
	else:
		capacity = maxi(0, SLOT_LIMIT - state.inventory.size()) * definition.max_stack
		for stack: Dictionary in state.inventory:
			if stack.item_id == String(item_id):
				capacity += definition.max_stack - int(stack.quantity)
	return MireTypes.success({"item_id": String(item_id), "requested": quantity, "fits": mini(capacity, quantity), "remaining": maxi(0, quantity - capacity), "capacity": capacity, "key_item": definition.category in KEYS})

## All-or-nothing unless allow_partial is explicitly requested by loot/rewards.
func stage_add(candidate: Dictionary, item_id: StringName, quantity: int, source_id: StringName = &"", allow_partial: bool = false) -> MireTypes.ActionResult:
	var preview := preview_add(item_id, quantity, candidate)
	if not preview.ok:
		return preview
	var added: int = preview.payload.fits
	if added == 0 or (added < quantity and not allow_partial):
		return MireTypes.failure(&"capacity", &"Make room before collecting this item.")
	var id := String(item_id)
	var definition: MireTypes.ItemDef = db.items[item_id]
	var result := MireTypes.success({"item_id": id, "requested": quantity, "added": added, "remaining": quantity - added, "stack_ids": []})
	if definition.category in KEYS:
		var source_flag := "pickup/" + String(source_id)
		if not source_id.is_empty() and candidate.evidence.get(source_flag, false):
			return MireTypes.failure(&"already_collected", &"That pickup was already collected.")
		candidate.key_items[id] = int(candidate.key_items.get(id, 0)) + added
		if not candidate.evidence.get(id, false):
			candidate.evidence[id] = true
			result.event(&"evidence_acquired", [item_id])
		if not source_id.is_empty():
			candidate.evidence[source_flag] = true
			result.event(&"evidence_acquired", [StringName(source_flag)])
	else:
		var remaining: int = added
		for stack: Dictionary in candidate.inventory:
			if remaining == 0:
				break
			if stack.item_id != id:
				continue
			var moved: int = mini(remaining, definition.max_stack - int(stack.quantity))
			if moved > 0:
				stack.quantity = int(stack.quantity) + moved
				remaining -= moved
				result.payload.stack_ids.append(String(stack.stack_id))
		while remaining > 0:
			var stack_id: String = "stack_%d" % int(candidate.next_stack)
			candidate.next_stack = int(candidate.next_stack) + 1
			var moved: int = mini(remaining, definition.max_stack)
			candidate.inventory.append({"stack_id": stack_id, "item_id": id, "quantity": moved})
			result.payload.stack_ids.append(stack_id)
			remaining -= moved
	return result.event(&"inventory_changed")

## Call inside the quest/economy owner's transaction alongside story/currency.
func stage_reward(candidate: Dictionary, item_id: StringName, quantity: int, delivery_id: StringName) -> MireTypes.ActionResult:
	if delivery_id.is_empty():
		return MireTypes.failure(&"invalid_delivery", &"A reward needs a stable delivery identity.")
	var preview := preview_add(item_id, quantity, candidate)
	if not preview.ok:
		return preview
	var id := String(delivery_id)
	var marker := "reward/" + id
	if candidate.evidence.get(marker, false):
		return MireTypes.success({"delivery_id": id, "already_rewarded": true})
	if candidate.pending_delivery.has(id):
		return MireTypes.failure(&"invalid_delivery", &"That delivery identity is already in use.")
	if preview.payload.key_item and preview.payload.remaining > 0:
		return MireTypes.failure(&"capacity", &"You already carry the authored quantity of this quest item.")
	var added: int = preview.payload.fits
	var result := MireTypes.success({"item_id": String(item_id), "delivery_id": id, "added": added, "pending": quantity - added})
	if added > 0:
		var received := stage_add(candidate, item_id, added, StringName("reward/" + id))
		if not received.ok:
			return received
		result.events.append_array(received.events)
	if quantity > added:
		candidate.pending_delivery[id] = {"item_id": String(item_id), "quantity": quantity - added}
		if added == 0:
			result.event(&"inventory_changed")
		result.event(&"feedback", ["Some rewards await collection in Unclaimed rewards."])
	else:
		result.event(&"feedback", ["Reward received."])
	candidate.evidence[marker] = true
	return result

func sale_check(candidate: Dictionary, stack_id: StringName, quantity: int) -> MireTypes.ActionResult:
	var stack := find_stack(stack_id, candidate)
	if stack.is_empty():
		return MireTypes.failure(&"not_owned", &"That item is no longer in your inventory.")
	var definition: MireTypes.ItemDef = db.items.get(StringName(stack.item_id))
	if definition == null or definition.category in KEYS:
		return MireTypes.failure(&"protected_item", &"Quest items cannot be sold or discarded.")
	if quantity <= 0 or quantity > int(stack.quantity):
		return MireTypes.failure(&"invalid_quantity", &"Choose an owned quantity.")
	if definition.category == &"weapon":
		var weapons: int = 0
		for owned: Dictionary in candidate.inventory:
			var owned_def: MireTypes.ItemDef = db.items.get(StringName(owned.item_id))
			if owned_def != null and owned_def.category == &"weapon":
				weapons += int(owned.quantity)
		if weapons - quantity < 1:
			return MireTypes.failure(&"last_weapon", &"Keep at least one melee weapon.")
	if String(stack_id) in candidate.equipment.values():
		return MireTypes.failure(&"equipped", &"Unequip this item before selling it.")
	return MireTypes.success({"item_id": String(stack.item_id), "quantity": quantity})

## Removal for sales or completed timed consumption; callers decide the price/use.
func stage_remove(candidate: Dictionary, stack_id: StringName, quantity: int) -> MireTypes.ActionResult:
	var valid := sale_check(candidate, stack_id, quantity)
	if not valid.ok:
		return valid
	for index: int in candidate.inventory.size():
		var stack: Dictionary = candidate.inventory[index]
		if stack.stack_id == String(stack_id):
			if int(stack.quantity) == quantity:
				candidate.inventory.remove_at(index)
			else:
				stack.quantity = int(stack.quantity) - quantity
			break
	return valid.event(&"inventory_changed")

## Quest hand-in only. Permanent evidence is deliberately retained.
func stage_remove_key(candidate: Dictionary, item_id: StringName, quantity: int) -> MireTypes.ActionResult:
	var definition: MireTypes.ItemDef = db.items.get(item_id)
	if definition == null or definition.category not in KEYS:
		return MireTypes.failure(&"not_key_item", &"That is not a quest item.")
	var id := String(item_id)
	var carried: int = int(candidate.key_items.get(id, 0))
	if quantity <= 0 or quantity > carried:
		return MireTypes.failure(&"not_owned", &"You do not have the required quest item.")
	if carried == quantity:
		candidate.key_items.erase(id)
	else:
		candidate.key_items[id] = carried - quantity
	return MireTypes.success({"item_id": id, "quantity": quantity}).event(&"inventory_changed")

func _next_action(kind: String) -> StringName:
	while true:
		_action_sequence += 1
		var id := "inventory/%s/%d" % [kind, _action_sequence]
		if not session.state.transactions.has(id):
			return StringName(id)
	return &""
