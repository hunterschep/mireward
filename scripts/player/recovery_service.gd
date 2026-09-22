class_name RecoveryService
extends RefCounted

signal consumption_started(item_id: StringName, duration: float)
signal consumption_finished(result: MireTypes.ActionResult)
signal death_ready
signal recovery_completed(reason: StringName, result: MireTypes.ActionResult)
signal autosave_requested(reason: StringName)

var session: Node
var db: Node
var player: MirePlayer
var _combat: CombatComponent
var _danger_provider: Callable
var _reset_encounters: Callable
var _travel_handler: Callable
var _consumption: Dictionary = {}
var _pending_recovery: Dictionary = {}
var _death_transaction: StringName
var _sequence: int = 0
var _owns_action_lock: bool = false

func _init(owner: Node) -> void:
	session = owner
	db = owner.get_node("/root/ContentDB")

func bind_runtime(controlled_player: MirePlayer, danger_provider: Callable, reset_encounters: Callable, travel_handler: Callable) -> MireTypes.ActionResult:
	if not is_instance_valid(controlled_player) or not controlled_player.combat is CombatComponent or not _callback(danger_provider, 0) or not _callback(reset_encounters, 0) or not _callback(travel_handler, 3):
		return MireTypes.failure(&"invalid_runtime", &"Recovery needs a player, danger check, encounter reset, and travel handler.")
	unbind_runtime()
	player = controlled_player
	_combat = player.combat
	_danger_provider = danger_provider
	_reset_encounters = reset_encounters
	_travel_handler = travel_handler
	_combat.hit_received.connect(_on_hit_received)
	_combat.died.connect(_on_died)
	return MireTypes.success()

func unbind_runtime() -> void:
	reset_runtime()
	if is_instance_valid(_combat):
		if _combat.hit_received.is_connected(_on_hit_received):
			_combat.hit_received.disconnect(_on_hit_received)
		if _combat.died.is_connected(_on_died):
			_combat.died.disconnect(_on_died)
	player = null
	_combat = null
	_danger_provider = Callable()
	_reset_encounters = Callable()
	_travel_handler = Callable()

func reset_runtime() -> void:
	cancel_consume(&"Session changed.")
	_pending_recovery.clear()
	_death_transaction = &""
	_release_lock()

func has_pending_recovery() -> bool:
	return not _pending_recovery.is_empty()

func is_consuming() -> bool:
	return not _consumption.is_empty()

func consumption_view() -> Dictionary:
	return _consumption.duplicate(true)

func start_consume(stack_id: StringName) -> MireTypes.ActionResult:
	if not _player_ready() or not session.active or float(session.state.player.health) <= 0:
		return MireTypes.failure(&"unavailable", &"Enter the world before using an item.")
	if is_consuming() or session.action_locked or session.travelling or session.transactions.active or not _pending_recovery.is_empty() or _combat.is_committed():
		return MireTypes.failure(&"action_locked", &"Finish the current action before using an item.")
	var stack: Dictionary = session.inventory.find_stack(stack_id)
	if stack.is_empty():
		return MireTypes.failure(&"not_owned", &"That item is no longer in your inventory.")
	var definition: MireTypes.ItemDef = db.items.get(StringName(stack.item_id))
	if definition == null or definition.category != &"consumable":
		return MireTypes.failure(&"not_consumable", &"This item cannot be consumed.")
	var resource: String = definition.data.resource
	if float(session.state.player[resource]) >= 100.0:
		return MireTypes.failure(&"resource_full", StringName("Your %s is already full." % resource))
	_consumption = {"stack_id": String(stack_id), "item_id": String(definition.id), "resource": resource, "amount": float(definition.data.restore_amount), "duration": float(definition.data.use_seconds), "elapsed": 0.0, "transaction_id": String(_next_action("consume"))}
	_combat.set_guard(false)
	_take_lock()
	consumption_started.emit(definition.id, float(_consumption.duration))
	return MireTypes.success({"item_id": String(definition.id), "duration": float(_consumption.duration), "started": true})

func quick_heal() -> MireTypes.ActionResult:
	for stack: Dictionary in session.state.inventory:
		if stack.item_id == "bandage":
			return start_consume(StringName(stack.stack_id))
	return MireTypes.failure(&"no_bandage", &"You have no bandages.")

func advance(delta: float) -> void:
	if not _pending_recovery.is_empty():
		return
	if not _player_ready() or not session.active or session.get_tree().paused or delta <= 0 or not is_finite(delta):
		return
	if player.input_enabled and player.controls.pressed(&"quick_heal"):
		var requested := quick_heal()
		if not requested.ok:
			session.get_node("/root/EventBus").feedback.emit(String(requested.message_key))
	if not is_consuming():
		return
	if float(session.state.player.health) <= 0 or session.travelling:
		cancel_consume(&"Item use interrupted.")
		return
	_consumption.elapsed = float(_consumption.elapsed) + delta
	player.gear.pose(&"healing", minf(1.0, float(_consumption.elapsed) / float(_consumption.duration)))
	if float(_consumption.elapsed) + 0.000001 >= float(_consumption.duration):
		_finish_consumption()

func cancel_consume(reason: StringName = &"Item use interrupted.") -> void:
	if not is_consuming():
		return
	_clear_consumption()
	consumption_finished.emit(MireTypes.failure(&"interrupted", reason))

func rest_offer(anchor_id: StringName) -> MireTypes.ActionResult:
	if not db.map.rest_points.has(String(anchor_id)):
		return MireTypes.failure(&"unknown_anchor", &"That rest point is not known.")
	if not _runtime_ready():
		return MireTypes.failure(&"unavailable", &"World recovery is not connected yet.")
	if not session.active or float(session.state.player.health) <= 0 or session.action_locked or session.travelling:
		return MireTypes.failure(&"action_locked", &"Finish the current action before resting.")
	var anchor: Dictionary = db.map.rest_points[String(anchor_id)]
	var at := Vector3(anchor.position[0], anchor.position[1], anchor.position[2])
	if session.state.player.scene_id != anchor.scene_id or player.global_position.distance_to(at) > 3.0:
		return MireTypes.failure(&"too_far", &"Move closer to this rest point.")
	var danger: Variant = _danger_provider.call()
	if not danger is bool:
		return MireTypes.failure(&"invalid_runtime", &"The nearby danger check failed.")
	if danger:
		return MireTypes.failure(&"unsafe", &"You cannot rest while a hostile is nearby or engaged.")
	var fee: int = 4 if anchor_id == &"inn_bed" and not session.state.flags.free_inn else 0
	if int(session.state.player.crowns) < fee:
		return MireTypes.failure(&"insufficient_crowns", &"The inn bed costs four crowns. Outdoor shrines are free.")
	return MireTypes.success({"anchor_id": String(anchor_id), "fee": fee})

func rest(anchor_id: StringName, transaction_id: StringName) -> MireTypes.ActionResult:
	if not _pending_recovery.is_empty():
		return retry_recovery() if _pending_recovery.transaction_id == String(transaction_id) else MireTypes.failure(&"busy", &"Finish the pending recovery first.")
	if session.state.transactions.has(String(transaction_id)):
		return _replay(transaction_id)
	var offer := rest_offer(anchor_id)
	if not offer.ok:
		return offer
	return _begin_recovery(anchor_id, &"rest", transaction_id)

func confirm_death() -> MireTypes.ActionResult:
	if not _pending_recovery.is_empty():
		return retry_recovery() if _pending_recovery.reason == "death" else MireTypes.failure(&"busy", &"Finish the pending recovery first.")
	if not _death_transaction.is_empty() and session.state.transactions.has(String(_death_transaction)) and float(session.state.player.health) > 0:
		return _replay(_death_transaction)
	if float(session.state.player.health) > 0 or not session.active:
		return MireTypes.failure(&"not_dead", &"There is no death to recover from.")
	if _death_transaction.is_empty():
		_death_transaction = _next_action("death")
	return _begin_recovery(StringName(session.state.player.rest_anchor), &"death", _death_transaction)

func retry_recovery() -> MireTypes.ActionResult:
	if _pending_recovery.is_empty():
		return MireTypes.failure(&"not_pending", &"There is no recovery waiting to finish.")
	if not _runtime_ready():
		return _pending_failure(&"World recovery is not connected. Reconnect it and retry.")
	if not _pending_recovery.reset_done:
		var reset: Variant = _reset_encounters.call()
		if not reset is MireTypes.ActionResult or not reset.ok:
			return _pending_failure(&"Progress was kept, but encounters could not reset. Retry recovery.")
		_pending_recovery.reset_done = true
	if _pending_recovery.travel_started:
		return _pending_result()
	var travelled: Variant = _travel_handler.call(StringName(_pending_recovery.anchor_id), StringName(_pending_recovery.reason), true)
	if not travelled is MireTypes.ActionResult or not travelled.ok:
		return _pending_failure(&"Progress was kept, but travel could not finish. Retry recovery.")
	if travelled.payload.get("pending", false) or session.travelling:
		var operation: Variant = travelled.payload.get("operation_id")
		if not session.travelling or not SessionValidation.identifier(operation):
			return _pending_failure(&"Pending travel needs an operation identity and input lock. Retry recovery.")
		_pending_recovery.travel_started = true
		_pending_recovery.operation_id = String(operation)
		return _pending_result()
	return _complete_recovery()

func finish_pending_travel(operation_id: StringName, result: MireTypes.ActionResult) -> MireTypes.ActionResult:
	if _pending_recovery.is_empty() or not _pending_recovery.travel_started or _pending_recovery.get("operation_id", "") != String(operation_id):
		return MireTypes.failure(&"stale_transition", &"That recovery transition is no longer pending.")
	if result == null or not result.ok:
		_pending_recovery.travel_started = false
		_pending_recovery.erase("operation_id")
		return _pending_failure(&"Progress was kept, but arrival failed. Retry recovery.")
	if session.travelling or result.payload.get("pending", false):
		return _pending_failure(&"Arrival has not finished yet.")
	return _complete_recovery()

func _complete_recovery() -> MireTypes.ActionResult:
	var result: MireTypes.ActionResult = _replay(StringName(_pending_recovery.transaction_id))
	var reason := StringName(_pending_recovery.reason)
	result.payload.erase("replayed")
	_pending_recovery.clear()
	_release_lock()
	_combat.reset_combat()
	player.vitals.reset()
	player.clear_input_edges()
	var danger: Variant = _danger_provider.call()
	if danger is bool:
		session.danger = danger
	recovery_completed.emit(reason, result)
	autosave_requested.emit(reason)
	return result

func _begin_recovery(anchor_id: StringName, reason: StringName, transaction_id: StringName) -> MireTypes.ActionResult:
	if transaction_id.is_empty():
		return MireTypes.failure(&"invalid_transaction", &"Recovery needs a transaction identity.")
	if not _runtime_ready() or not db.map.rest_points.has(String(anchor_id)):
		return MireTypes.failure(&"unavailable", &"A valid rest anchor and world recovery handler are required.")
	var prepared: Variant = _travel_handler.call(anchor_id, reason, false)
	if not prepared is MireTypes.ActionResult:
		return MireTypes.failure(&"invalid_runtime", &"The recovery route could not be checked.")
	if not prepared.ok:
		return prepared
	var result: MireTypes.ActionResult = session.transactions.run(transaction_id, func(candidate: Dictionary) -> MireTypes.ActionResult:
		var charged: int = 0
		if reason == &"rest":
			var current := rest_offer(anchor_id)
			if not current.ok:
				return current
			charged = int(current.payload.fee)
		elif float(candidate.player.health) > 0:
			return MireTypes.failure(&"not_dead", &"There is no death to recover from.")
		else:
			charged = mini(12, floori(float(candidate.player.crowns) * 0.10))
		var anchor: Dictionary = db.map.rest_points[String(anchor_id)]
		candidate.player.crowns = int(candidate.player.crowns) - charged
		candidate.player.health = 100.0
		candidate.player.stamina = 100.0
		candidate.player.rest_anchor = String(anchor_id)
		candidate.player.scene_id = String(anchor.scene_id)
		candidate.player.position = anchor.position.duplicate()
		candidate.player.yaw = 0.0
		var staged := MireTypes.success({"anchor_id": String(anchor_id), "reason": String(reason), "charged": charged, "transaction_id": String(transaction_id), "committed": true})
		if charged > 0:
			staged.event(&"currency_changed")
		return staged
	)
	if not result.ok:
		return result
	_pending_recovery = {"anchor_id": String(anchor_id), "reason": String(reason), "transaction_id": String(transaction_id), "reset_done": false, "travel_started": false}
	_take_lock()
	return retry_recovery()

func _finish_consumption() -> void:
	var use: Dictionary = _consumption.duplicate(true)
	var result: MireTypes.ActionResult = session.transactions.run(StringName(use.transaction_id), func(candidate: Dictionary) -> MireTypes.ActionResult:
		if float(candidate.player.health) <= 0 or session.travelling:
			return MireTypes.failure(&"interrupted", &"Item use was interrupted.")
		var stack: Dictionary = session.inventory.find_stack(StringName(use.stack_id), candidate)
		if stack.is_empty() or stack.item_id != use.item_id:
			return MireTypes.failure(&"not_owned", &"That item is no longer available.")
		var before: float = float(candidate.player[use.resource])
		if before >= 100.0:
			return MireTypes.failure(&"resource_full", &"That resource is already full.")
		var removed: MireTypes.ActionResult = session.inventory.stage_remove(candidate, StringName(use.stack_id), 1)
		if not removed.ok:
			return removed
		candidate.player[use.resource] = minf(100.0, before + float(use.amount))
		removed.payload.merge({"resource": use.resource, "restored": float(candidate.player[use.resource]) - before})
		return removed
	)
	_clear_consumption()
	if result.ok:
		session.get_node("/root/AudioService").play_event(&"bandage", player.global_position)
	consumption_finished.emit(result)

func _clear_consumption() -> void:
	_consumption.clear()
	_release_lock()
	if _player_ready():
		player.gear.pose(&"idle")

func _on_hit_received(_request: MireTypes.DamageRequest, result: MireTypes.DamageResult) -> void:
	if result.health_damage > 0:
		cancel_consume(&"Damage interrupted item use; the item was kept.")

func _on_died(_entity_id: StringName) -> void:
	if float(session.state.player.health) > 0:
		return
	cancel_consume(&"Death interrupted item use; the item was kept.")
	if _death_transaction.is_empty() or session.state.transactions.has(String(_death_transaction)):
		_death_transaction = _next_action("death")
		death_ready.emit()

func _take_lock() -> void:
	_owns_action_lock = true
	session.action_locked = true

func _release_lock() -> void:
	if _owns_action_lock:
		_owns_action_lock = false
		session.action_locked = session.travelling or (is_instance_valid(_combat) and (_combat.is_committed() or _combat.stagger_remaining > 0.0))

func _player_ready() -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and not player.is_queued_for_deletion() and is_instance_valid(_combat)

func _runtime_ready() -> bool:
	return _player_ready() and _callback(_danger_provider, 0) and _callback(_reset_encounters, 0) and _callback(_travel_handler, 3)

func _callback(callback: Callable, count: int) -> bool:
	return callback.is_valid() and callback.get_argument_count() == count

func _next_action(kind: String) -> StringName:
	while true:
		_sequence += 1
		var id := "recovery/%s/%d" % [kind, _sequence]
		if not session.state.transactions.has(id):
			return StringName(id)
	return &""

func _replay(transaction_id: StringName) -> MireTypes.ActionResult:
	var result: MireTypes.ActionResult = session.transactions.run(transaction_id, func(_candidate: Dictionary) -> MireTypes.ActionResult:
		return MireTypes.failure(&"missing_receipt", &"The recovery receipt is missing.")
	)
	if result.ok:
		result.payload.merge({"pending": false, "complete": true}, true)
	return result

func _pending_result() -> MireTypes.ActionResult:
	return MireTypes.success({"committed": true, "pending": true, "complete": false, "transaction_id": _pending_recovery.transaction_id, "operation_id": _pending_recovery.get("operation_id", "")}, &"Recovery is waiting for travel to finish.")

func _pending_failure(message: StringName) -> MireTypes.ActionResult:
	return MireTypes.ActionResult.new(false, &"recovery_pending", message, {"committed": true, "pending": true, "complete": false, "transaction_id": _pending_recovery.transaction_id})
