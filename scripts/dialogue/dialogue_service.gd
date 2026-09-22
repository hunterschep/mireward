class_name DialogueService
extends RefCounted
## Dialogue owns transient presentation state; quest services own every mutation.

const Rules = preload("res://scripts/dialogue/dialogue_rules.gd")
var session: Node
var db: Node
var npc_id: StringName = &""
var node_id: StringName = &""
var _definition: Dictionary = {}
var _nodes: Dictionary = {}

func _init(owner: Node) -> void:
	session = owner
	db = owner.get_node("/root/ContentDB")

func start(speaker_id: StringName) -> MireTypes.ActionResult:
	if not db.dialogues.has(speaker_id):
		return _failure(&"unknown_speaker", "That speaker is not available.")
	if speaker_id == &"captain_rusk" and session.state.world.get("captain_hall_captain_rusk_01", {}).get("defeated", false):
		return _failure(&"unavailable", "The captain has already been defeated.")
	var definition: Dictionary = db.dialogues[speaker_id].data
	var errors: PackedStringArray = Rules.validate(definition, db)
	if not errors.is_empty():
		return _failure(&"invalid_dialogue", "; ".join(errors))
	close()
	npc_id = speaker_id
	_definition = definition.duplicate(true)
	for node: Dictionary in _definition.nodes:
		_nodes[node.id] = node
	node_id = StringName(_greeting(_definition).id)
	return _result()

func choose(requested_node: StringName, choice_id: StringName) -> MireTypes.ActionResult:
	if npc_id.is_empty() or requested_node != StringName(String(npc_id) + "/" + String(node_id)) or not _nodes.has(String(node_id)):
		return _failure(&"stale_dialogue", "This conversation changed. Open the current choices again.")
	if choice_id == &"@leave":
		close()
		return MireTypes.success({"ui_action": "close_dialogue", "dialogue": {}})
	var node: Dictionary = _nodes[String(node_id)]
	if not Rules.matches(node.conditions, session.state, db):
		return _stale()
	var selected: Dictionary = {}
	for choice: Dictionary in _choices(node):
		if choice.id == String(choice_id):
			selected = choice
			break
	if selected.is_empty():
		return _stale()
	var outcome: MireTypes.ActionResult = _commit(selected.effect)
	if not outcome.ok:
		return outcome
	var domain: Dictionary = outcome.payload.duplicate(true)
	if selected.next == "@close":
		close()
	else:
		node_id = StringName(_greeting(_definition).id if selected.next == "@root" else selected.next)
	var result: MireTypes.ActionResult = _result()
	result.payload["outcome"] = domain
	if domain.has("ui_action"):
		for key: String in domain:
			result.payload[key] = domain[key]
	return result

func close() -> void:
	npc_id = &""
	node_id = &""
	_definition.clear()
	_nodes.clear()

func view() -> Dictionary:
	if npc_id.is_empty():
		return {}
	var node: Dictionary = _nodes[String(node_id)]
	if not Rules.matches(node.conditions, session.state, db):
		node = _greeting(_definition)
		node_id = StringName(node.id)
	var choices: Array[Dictionary] = []
	for choice: Dictionary in _choices(node):
		choices.append({"id": choice.id, "text": choice.text})
	choices.append({"id": "@leave", "text": "Leave."})
	return {"npc_id": String(npc_id), "speaker_name": _definition.speaker_name, "node_id": String(npc_id) + "/" + String(node_id), "text": node.text, "choices": choices, "confirmation": node.confirmation, "max_visible_choices": 3}

func npc_view(speaker_id: StringName) -> Dictionary:
	if not db.dialogues.has(speaker_id):
		return {}
	var definition: Dictionary = db.dialogues[speaker_id].data
	if not Rules.validate(definition, db).is_empty():
		return {}
	var greeting: Dictionary = _greeting(definition)
	var priority: String = greeting.priority
	return {"npc_id": String(speaker_id), "speaker_name": definition.speaker_name, "marker": "turn_in" if priority == "turn_in" else "quest" if priority in ["active", "main", "side"] else "none"}

func _greeting(definition: Dictionary) -> Dictionary:
	var selected: Dictionary = {}
	var priority: int = -1
	for node: Dictionary in definition.nodes:
		if node.greeting and int(Rules.PRIORITIES[node.priority]) > priority and Rules.matches(node.conditions, session.state, db):
			selected = node
			priority = int(Rules.PRIORITIES[node.priority])
	return selected

func _choices(node: Dictionary) -> Array[Dictionary]:
	var candidates: Array = node.choices.duplicate(true)
	if not node.confirmation:
		candidates.append_array(_definition.topics)
	var available: Array[Dictionary] = []
	for choice: Dictionary in candidates:
		if choice.next != String(node_id) and Rules.matches(choice.conditions, session.state, db):
			available.append(choice)
	return available

func _commit(effect: Dictionary) -> MireTypes.ActionResult:
	if effect.is_empty():
		return MireTypes.success()
	match effect.op:
		"activate":
			if db.quests[StringName(effect.quest_id)].data.giver_id != String(npc_id):
				return _failure(&"wrong_speaker", "Speak to this quest's giver.")
			return session.quests.activate(StringName(effect.quest_id))
		"complete":
			if db.quests[StringName(effect.quest_id)].data.turn_in_npc_id != String(npc_id):
				return _failure(&"wrong_speaker", "Return to the character named in the journal.")
			return session.quests.complete(StringName(effect.quest_id), StringName("dialogue/" + String(npc_id) + "/" + String(node_id)))
		"conversation":
			var result: MireTypes.ActionResult = session.quests.record_conversation(npc_id, StringName(effect.step_id))
			if result.ok and effect.step_id == QuestPredicates.MQ05 + "/challenge_rusk":
				result.payload.merge({"ui_action": "challenge_rusk", "entity_id": "captain_hall_captain_rusk_01", "command_pending": true})
			return result
		"choose":
			return session.quests.choose(StringName(effect.choice_id), StringName(effect.value), StringName("dialogue/" + String(npc_id) + "/" + String(node_id)))
		"command":
			if effect.command == "shop" and effect.shop_id == String(npc_id) and db.shops.has(effect.shop_id):
				return MireTypes.success({"ui_action": "shop", "shop_id": effect.shop_id, "command_pending": true})
			if effect.command == "rest" and npc_id == &"tamsin_reed" and effect.rest_id == "inn_bed":
				return MireTypes.success({"ui_action": "rest", "rest_id": "inn_bed", "cost": 0 if session.state.flags.free_inn else 4, "command_pending": true})
	return _failure(&"unsupported_effect", "This dialogue action is not supported.")

func _result() -> MireTypes.ActionResult:
	return MireTypes.success({"ui_action": "close_dialogue" if npc_id.is_empty() else "dialogue", "dialogue": view()})

func _stale() -> MireTypes.ActionResult:
	var result := _failure(&"stale_choice", "That option is no longer available. Review the current choices.")
	result.payload["dialogue"] = view()
	return result

func _failure(code: StringName, message: String) -> MireTypes.ActionResult:
	return MireTypes.failure(code, StringName(message))
