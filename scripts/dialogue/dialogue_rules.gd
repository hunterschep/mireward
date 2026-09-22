class_name DialogueRules
extends RefCounted
## The dialogue authoring boundary and its finite set of state predicates.

const PRIORITIES := {"turn_in": 500, "active": 400, "main": 300, "side": 200, "aftermath": 100, "ordinary": 0}
const FLAGS := ["puzzle_solved", "free_inn", "shelter_lights", "restored_badge", "undercroft_open"]
const DESTINATIONS := ["@root", "@close"]

static func validate_definitions(db: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	for id: StringName in db.dialogues:
		errors.append_array(validate(db.dialogues[id].data, db))
	return errors

static func validate(definition: Dictionary, db: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	var npc: String = str(definition.get("npc_id", ""))
	if not SessionValidation.json_safe(definition) or not SessionValidation.identifier(definition.get("id")) or not SessionValidation.identifier(definition.get("npc_id")) or definition.id != definition.npc_id or not db.dialogues.has(StringName(npc)):
		return PackedStringArray(["Dialogue requires matching known speaker and dialogue IDs: " + npc])
	if definition.get("foundation_only", false):
		errors.append("Dialogue is still a reservation: " + npc)
	if not SessionValidation.identifier(definition.get("speaker_name")):
		errors.append("Dialogue speaker_name is missing: " + npc)
	if not definition.get("nodes") is Array or not definition.get("topics") is Array:
		return PackedStringArray(["Dialogue nodes and topics must be lists: " + npc])
	var nodes: Dictionary = {}
	var ordinary: bool = false
	for row: Variant in definition.nodes:
		if not row is Dictionary or not SessionValidation.identifier(row.get("id")):
			errors.append("Invalid dialogue node: " + npc)
			continue
		var label: String = npc + "/" + row.id
		if nodes.has(row.id) or row.id.begins_with("@"):
			errors.append("Duplicate or reserved dialogue node ID: " + label)
		nodes[row.id] = row
		_text(row.get("text"), label, errors)
		_conditions(row.get("conditions"), label, db, errors)
		if not row.get("greeting") is bool or not row.get("confirmation") is bool or not PRIORITIES.has(row.get("priority")):
			errors.append("Invalid greeting, confirmation, or priority: " + label)
		if row.get("greeting") is bool and row.greeting and row.get("priority") is String and row.priority == "ordinary" and row.get("conditions") is Array and row.conditions.is_empty():
			ordinary = true
		if not row.get("choices") is Array:
			errors.append("Dialogue choices must be a list: " + label)
	if not ordinary:
		errors.append("Dialogue needs an unconditional ordinary greeting: " + npc)
	var topics: Dictionary = {}
	_validate_choices(definition.topics, npc + "/topics", npc, false, nodes, topics, db, errors)
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		if node.get("choices") is Array:
			_validate_choices(node.choices, npc + "/" + id, npc, node.get("confirmation") is bool and node.confirmation, nodes, topics.duplicate(), db, errors)
		if node.get("confirmation") is bool and node.confirmation and node.get("choices") is Array:
			var confirms: int = 0
			var cancels: int = 0
			for choice: Variant in node.choices:
				if choice is Dictionary and choice.get("effect") is Dictionary:
					confirms += int(choice.effect.get("op") is String and choice.effect.op == "choose")
					cancels += int(choice.effect.is_empty())
			if confirms != 1 or cancels < 1:
				errors.append("Confirmation needs one commit and a no-effect cancel: " + npc + "/" + id)
	var reachable: Dictionary = {}
	var pending: Array[String] = []
	for id: String in nodes:
		if nodes[id].get("greeting") is bool and nodes[id].greeting:
			pending.append(id)
	for choice: Variant in definition.topics:
		if choice is Dictionary and choice.get("next") is String and nodes.has(choice.next):
			pending.append(choice.next)
	while not pending.is_empty():
		var id: String = pending.pop_back()
		if reachable.has(id):
			continue
		reachable[id] = true
		if not nodes[id].get("choices") is Array:
			continue
		for choice: Variant in nodes[id].choices:
			if choice is Dictionary and choice.get("next") is String and nodes.has(choice.next):
				pending.append(choice.next)
	for id: String in nodes:
		if not reachable.has(id):
			errors.append("Unreachable dialogue node: " + npc + "/" + id)
	if definition.has("combat_lines"):
		if npc != "captain_rusk" or not definition.combat_lines is Dictionary:
			errors.append("Only Rusk has authored combat_lines.")
		else:
			for key: Variant in definition.combat_lines:
				_text(definition.combat_lines[key], npc + "/combat_lines/" + str(key), errors)
	return errors

static func _validate_choices(rows: Array, label: String, npc: String, confirmation: bool, nodes: Dictionary, used: Dictionary, db: Node, errors: PackedStringArray) -> void:
	for choice: Variant in rows:
		if not choice is Dictionary or not SessionValidation.identifier(choice.get("id")):
			errors.append("Invalid dialogue choice: " + label)
			continue
		var here: String = label + "/" + choice.id
		if used.has(choice.id) or choice.id.begins_with("@"):
			errors.append("Duplicate or reserved dialogue choice ID: " + here)
		used[choice.id] = true
		_text(choice.get("text"), here, errors)
		_conditions(choice.get("conditions"), here, db, errors)
		if not SessionValidation.identifier(choice.get("next")) or (choice.next not in DESTINATIONS and not nodes.has(choice.next)):
			errors.append("Missing dialogue destination: " + here)
		if not choice.get("effect") is Dictionary:
			errors.append("Dialogue choice requires one effect dictionary: " + here)
		else:
			_effect(choice.effect, here, npc, confirmation, db, errors)

static func _conditions(value: Variant, label: String, db: Node, errors: PackedStringArray) -> void:
	if not value is Array:
		errors.append("Dialogue conditions must be a list: " + label)
		return
	for condition: Variant in value:
		if not condition is Dictionary or not valid_condition(condition, db):
			errors.append("Unknown or malformed dialogue condition: " + label)

static func valid_condition(condition: Dictionary, db: Node) -> bool:
	match condition.get("op"):
		"quest_state":
			if not _quest(condition.get("id"), db) or not condition.get("states") is Array or condition.states.is_empty():
				return false
			for state: Variant in condition.states:
				if state not in QuestPredicates.STATES:
					return false
			return true
		"objective_pending":
			return not objective(condition.get("id"), db).is_empty()
		"choice":
			if not condition.get("id") is String or not QuestPredicates.CHOICES.has(condition.id) or not condition.get("value") is String:
				return false
			return condition.value in QuestPredicates.CHOICES[condition.id] or condition.value == ("none" if condition.id == "ending" else "unset")
		"flag":
			return condition.get("id") in FLAGS and condition.get("value") is bool
		"alive":
			if not condition.get("id") is String:
				return false
			for spawn: Dictionary in db.map.spawns:
				if spawn.id == condition.id:
					return true
	return false

static func _effect(effect: Dictionary, label: String, npc: String, confirmation: bool, db: Node, errors: PackedStringArray) -> void:
	if effect.is_empty():
		return
	var valid: bool = false
	match effect.get("op"):
		"activate", "complete":
			if _quest(effect.get("quest_id"), db):
				var quest: Dictionary = db.quests[StringName(effect.quest_id)].data
				valid = quest.giver_id == npc if effect.op == "activate" else quest.turn_in_npc_id == npc and effect.quest_id not in [QuestPredicates.SQ06, QuestPredicates.MQ06]
		"conversation":
			valid = effect.get("step_id") is String and QuestPredicates.CONVERSATIONS.get(effect.step_id) == npc
		"choose":
			if confirmation and effect.get("choice_id") is String and QuestPredicates.CHOICES.has(effect.choice_id) and effect.get("value") is String:
				valid = effect.get("value") in QuestPredicates.CHOICES[effect.choice_id]
				valid = valid and ((effect.choice_id == "wren_terms" and npc == "wren_kest") or (effect.choice_id == "medicine_recipient" and npc == ("wren_kest" if effect.get("value") == "camp" else "mara_venn")))
		"command":
			match effect.get("command"):
				"shop": valid = effect.get("shop_id") is String and effect.shop_id == npc and db.shops.has(npc)
				"rest": valid = npc == "tamsin_reed" and effect.get("rest_id") is String and effect.rest_id == "inn_bed"
	if not valid:
		errors.append("Unknown, misplaced, or unconfirmed dialogue effect: " + label)

static func matches(conditions: Array, state: Dictionary, db: Node) -> bool:
	for condition: Dictionary in conditions:
		match condition.op:
			"quest_state":
				if state.quests[condition.id].state not in condition.states: return false
			"objective_pending":
				var quest_id: String = condition.id.get_slice("/", 0)
				if state.quests[quest_id].state not in ["ACTIVE", "READY"]: return false
				for step: Dictionary in db.quests[StringName(quest_id)].data.objectives:
					if step.id == condition.id:
						if QuestPredicates.satisfied(step, state): return false
						break
					if not QuestPredicates.satisfied(step, state): return false
			"choice":
				if state.choices[condition.id] != condition.value: return false
			"flag":
				if state.flags[condition.id] != condition.value: return false
			"alive":
				if state.world.get(condition.id, {}).get("defeated", false): return false
			_: return false
	return true

static func objective(id: Variant, db: Node) -> Dictionary:
	if not id is String:
		return {}
	var quest_id: String = id.get_slice("/", 0)
	if not _quest(quest_id, db):
		return {}
	for row: Dictionary in db.quests[StringName(quest_id)].data.objectives:
		if row.id == id:
			return row
	return {}

static func _quest(id: Variant, db: Node) -> bool:
	return id is String and db.quests.has(StringName(id))

static func _text(value: Variant, label: String, errors: PackedStringArray) -> void:
	if not SessionValidation.identifier(value):
		errors.append("Dialogue text is missing: " + label)
	elif value.replace("\n", " ").replace("\r", " ").replace("\t", " ").split(" ", false).size() > 45:
		errors.append("Dialogue line exceeds 45 words: " + label)
