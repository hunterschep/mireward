class_name Transactions
extends RefCounted

var session: Node
var active: bool = false

func _init(owner: Node) -> void:
	session = owner

func run(transaction_id: StringName, stage: Callable) -> MireTypes.ActionResult:
	if transaction_id.is_empty():
		return MireTypes.failure(&"invalid_transaction", &"The action needs a transaction ID.")
	if active:
		return MireTypes.failure(&"busy", &"Another action is still committing.")
	if not session.state.get("transactions") is Dictionary:
		return MireTypes.failure(&"invalid_state", &"The transaction ledger is damaged.")
	var key := String(transaction_id)
	if session.state.transactions.has(key):
		var saved: Variant = session.state.transactions[key]
		if not SessionValidation.receipt(saved):
			return MireTypes.failure(&"invalid_state", &"The transaction receipt is damaged.")
		var payload: Dictionary = saved.payload.duplicate(true)
		payload["replayed"] = true
		return MireTypes.ActionResult.new(true, StringName(saved.code), StringName(saved.message_key), payload)
	if not stage.is_valid() or stage.get_argument_count() != 1:
		return MireTypes.failure(&"invalid_transaction", &"The action needs a valid one-argument transaction stage.")
	active = true
	var candidate: Dictionary = session.state.duplicate(true)
	var staged: Variant = stage.call(candidate)
	if not staged is MireTypes.ActionResult:
		active = false
		return MireTypes.failure(&"invalid_transaction", &"The action did not return an ActionResult.")
	var result: MireTypes.ActionResult = staged
	if result.ok and not valid_events(result.events):
		result = MireTypes.failure(&"invalid_transaction", &"The action contains an invalid notification.")
	if result.ok:
		if not candidate.get("transactions") is Dictionary or candidate.transactions != session.state.transactions:
			result = MireTypes.failure(&"invalid_state", &"Only the coordinator may change completed transaction receipts.")
		else:
			candidate.transactions[key] = {"code": String(result.code), "message_key": String(result.message_key), "payload": result.payload.duplicate(true)}
			var valid: MireTypes.ActionResult = session.validate_snapshot(candidate)
			if not valid.ok:
				result = valid
	if result.ok:
		# Neither a retained staging dictionary nor a returned payload can edit live state.
		session.state = candidate.duplicate(true)
		result.payload = result.payload.duplicate(true)
	active = false
	if result.ok:
		session.get_node("/root/EventBus").publish(result.events)
	return result

func valid_events(events: Array[Dictionary]) -> bool:
	var bus: Node = session.get_node("/root/EventBus")
	var signatures: Dictionary = {}
	for definition: Dictionary in bus.get_script().get_script_signal_list():
		signatures[StringName(definition.name)] = definition.args
	for event: Dictionary in events:
		var name: Variant = event.get("name")
		if (not name is String and not name is StringName) or not signatures.has(StringName(name)) or not event.get("args") is Array:
			return false
		var arguments: Array = event.args
		var parameters: Array = signatures[StringName(name)]
		if arguments.size() != parameters.size():
			return false
		for index: int in arguments.size():
			var value: Variant = arguments[index]
			var expected: int = parameters[index].type
			if typeof(value) != expected and not (expected == TYPE_STRING_NAME and value is String):
				return false
	return true
