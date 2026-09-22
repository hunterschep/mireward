class_name QuestPredicates
extends RefCounted
## Pure, whitelisted quest predicates and the save/content boundary for story data.

const STATES := ["LOCKED", "AVAILABLE", "ACTIVE", "READY", "COMPLETED"]
const CHOICES := {"wren_terms": ["amnesty", "restitution"], "medicine_recipient": ["camp", "village"], "ending": ["charter", "warden", "free_road"]}
const EFFECT_FLAGS := ["free_inn", "shelter_lights", "restored_badge"]
const READABLES := ["southern_sign", "toll_notice", "toll_receipt", "abbey_inscription", "orra_charter", "grain_ledger", "ferry_ledger", "captains_order", "broken_bell_plaque", "village_writ_table"]
const MQ03 := "mq_03_a_bell_without_rope"
const MQ04 := "mq_04_names_in_the_ledger"
const MQ05 := "mq_05_a_debt_in_stone"
const MQ06 := "mq_06_the_last_toll"
const SQ06 := "sq_06_no_clean_hands"
const MAIN_QUESTS := ["mq_01_bread_and_iron", "mq_02_the_kings_due", MQ03, MQ04, MQ05, MQ06]
const CONVERSATIONS := {
	MQ03 + "/request_charter": "sister_elian",
	MQ04 + "/meet_wren": "wren_kest",
	MQ05 + "/present_evidence": "ada_vey",
	MQ05 + "/challenge_rusk": "captain_rusk",
	MQ06 + "/discuss_resolution": "mara_venn",
}

static func count(predicate: Dictionary, state: Dictionary) -> int:
	var id: String = predicate.get("id", "")
	match predicate.get("op"):
		"evidence": return int(state.evidence.get(id, false))
		"read": return int(state.evidence.get("read/" + id, false))
		"conversation": return int(state.evidence.get("conversation/" + id, false))
		"flag": return int(state.flags.get(id, false))
		"choice": return int(state.choices.get(id, "") in CHOICES.get(id, []))
		"defeated": return int(state.world.get(id, {}).get("defeated", false))
		"sources":
			var found: int = 0
			for source: String in predicate.get("ids", []):
				found += int(state.evidence.get(source, false))
			return found
	return 0

static func satisfied(objective: Dictionary, state: Dictionary) -> bool:
	return count(objective.predicate, state) >= int(objective.count)

static func prerequisites_met(definition: Dictionary, state: Dictionary) -> bool:
	for id: String in definition.prerequisites:
		if state.quests.get(id, {}).get("state") != "COMPLETED":
			return false
	return true

static func ready(definition: Dictionary, state: Dictionary) -> bool:
	for objective: Dictionary in definition.objectives:
		if not objective.turn_in and not satisfied(objective, state):
			return false
	return true

static func completion_id(quest_id: String) -> StringName:
	return StringName("quest/" + quest_id + "/completion")

static func validate_definitions(db: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	var world: Variant = db.get("map")
	if not world is Dictionary or not world.get("scenes") is Dictionary or not world.get("spawns") is Array or not world.get("exterior") is Dictionary or not world.exterior.get("portals") is Array:
		errors.append("Quest validation requires an available world scene and portal registry.")
		return errors
	var objectives: Dictionary = {}
	var portals: Dictionary = {}
	for portal: Variant in world.exterior.portals:
		if not portal is Dictionary or not SessionValidation.identifier(portal.get("id")):
			errors.append("Malformed exterior portal in quest validation.")
			continue
		portals[portal.id] = true
	for quest_id: StringName in db.quests:
		var definition: Dictionary = db.quests[quest_id].data
		if not SessionValidation.json_safe(definition):
			errors.append("Non-JSON or nonfinite quest data: " + String(quest_id))
			continue
		if not definition.get("foundation_only", false) is bool:
			errors.append("Invalid quest reservation marker: " + String(quest_id))
			continue
		if definition.get("foundation_only", false):
			errors.append("Quest is still a reservation: " + String(quest_id))
			continue
		var metadata_valid: bool = true
		for field: String in ["name", "giver_id", "giver_location", "giver_scene_id"]:
			if not SessionValidation.identifier(definition.get(field)):
				metadata_valid = false
		if not definition.get("turn_in_npc_id") is String or not definition.get("prerequisites") is Array or not definition.get("objectives") is Array or not definition.get("consume") is Dictionary or not definition.get("rewards") is Dictionary or not definition.get("completion_effects") is Array:
			metadata_valid = false
		if not metadata_valid:
			errors.append("Invalid quest metadata: " + String(quest_id))
			continue
		if not db.dialogues.has(StringName(definition.giver_id)) or definition.objectives.is_empty():
			errors.append("Quest needs a known giver and objectives: " + String(quest_id))
		if not world.scenes.has(definition.giver_scene_id):
			errors.append("Quest giver needs a valid scene: " + String(quest_id))
		var main_index: int = MAIN_QUESTS.find(String(quest_id))
		var expected_prerequisites: Array = [MAIN_QUESTS[main_index - 1]] if main_index > 0 else []
		if definition.prerequisites.size() != expected_prerequisites.size():
			errors.append("Quest prerequisites differ from the canonical sequence: " + String(quest_id))
		else:
			for index: int in expected_prerequisites.size():
				var prerequisite: Variant = definition.prerequisites[index]
				if not prerequisite is String or prerequisite != expected_prerequisites[index]:
					errors.append("Quest prerequisites differ from the canonical sequence: " + String(quest_id))
		var turn_in_count: int = 0
		for objective_index: int in definition.objectives.size():
			var objective: Variant = definition.objectives[objective_index]
			if not objective is Dictionary or not SessionValidation.identifier(objective.get("id")) or not objective.get("predicate") is Dictionary or not ContentValidation.positive_integer(objective.get("count")) or not objective.get("turn_in") is bool:
				errors.append("Invalid objective in " + String(quest_id))
				continue
			var fields_valid: bool = true
			for field: String in ["label", "target_id", "location", "scene_id"]:
				if not SessionValidation.identifier(objective.get(field)):
					fields_valid = false
			for field: String in ["portal_id", "npc_id", "item_id", "alternative_target_id"]:
				if objective.has(field) and not SessionValidation.identifier(objective[field]):
					fields_valid = false
			if not fields_valid or not valid_predicate(objective.predicate, db):
				errors.append("Invalid objective fields or predicate: " + String(objective.id))
				continue
			if not objective.id.begins_with(String(quest_id) + "/") or objectives.has(objective.id):
				errors.append("Invalid or duplicate objective ID: " + String(objective.id))
			objectives[objective.id] = true
			if not world.scenes.has(objective.scene_id):
				errors.append("Unknown objective scene: " + String(objective.id))
			if objective.scene_id != "exterior" and not objective.has("portal_id"):
				errors.append("Indoor objective needs an exterior portal: " + String(objective.id))
			if objective.has("portal_id") and not portals.has(objective.portal_id):
				errors.append("Unknown objective portal: " + String(objective.id))
			if objective.has("npc_id") and not db.dialogues.has(StringName(objective.npc_id)):
				errors.append("Unknown objective speaker: " + String(objective.id))
			var operation: String = objective.predicate.op
			if operation == "conversation":
				if not objective.has("npc_id") or objective.predicate.id != objective.id or (not objective.turn_in and CONVERSATIONS.get(objective.id, "") != objective.npc_id) or (objective.turn_in and objective.npc_id != definition.turn_in_npc_id):
					errors.append("Unknown conversation step or turn-in speaker: " + String(objective.id))
			if objective.has("item_id"):
				var source: Variant = db.containers.get(objective.target_id)
				if not source is Dictionary or not source.get("items") is Dictionary or not SessionValidation.whole(source.items.get(objective.item_id)) or int(source.items[objective.item_id]) != 1:
					errors.append("Acquisition objective lacks its fixed item source: " + String(objective.id))
				if operation == "sources":
					for flag: String in objective.predicate.ids:
						var pickup: Variant = db.containers.get(flag.trim_prefix("pickup/"))
						if not pickup is Dictionary or not pickup.get("items") is Dictionary or not SessionValidation.whole(pickup.items.get(objective.item_id)) or int(pickup.items[objective.item_id]) != 1:
							errors.append("Counted pickup contains the wrong item: " + String(objective.id))
			if int(objective.count) != (objective.predicate.ids.size() if operation == "sources" else 1):
				errors.append("Invalid predicate count: " + String(objective.id))
			if objective.turn_in:
				turn_in_count += 1
				if objective_index != definition.objectives.size() - 1 or operation not in ["conversation", "choice"]:
					errors.append("Turn-in must be the final conversation or choice: " + String(objective.id))
		if turn_in_count != 1:
			errors.append("Quest needs exactly one final turn-in: " + String(quest_id))
		var rewards: Dictionary = definition.rewards
		if not ContentValidation.nonnegative_integer(rewards.get("crowns")) or not rewards.get("items") is Dictionary:
			errors.append("Invalid rewards: " + String(quest_id))
		else:
			for item: String in rewards.items:
				if not db.items.has(StringName(item)) or not ContentValidation.positive_integer(rewards.items[item]) or db.items[StringName(item)].category in InventoryService.KEYS:
					errors.append("Invalid reward item: " + item)
		for item: String in definition.consume:
			if not db.items.has(StringName(item)) or db.items[StringName(item)].category != &"quest" or not ContentValidation.positive_integer(definition.consume[item]):
				errors.append("Invalid quest hand-in item: " + item)
		for effect: Variant in definition.completion_effects:
			if not effect is Dictionary or not effect.get("op") is String or not effect.get("id") is String or not effect.get("value") is bool:
				errors.append("Malformed completion effect: " + String(quest_id))
				continue
			if effect.op != "flag" or effect.id not in EFFECT_FLAGS or not effect.value:
				errors.append("Unknown completion effect: " + String(quest_id))
	return errors

static func valid_predicate(predicate: Dictionary, db: Node) -> bool:
	if not SessionValidation.json_safe(predicate) or not predicate.get("op") is String or not predicate.get("id", "") is String:
		return false
	var id: String = predicate.get("id", "")
	var operation: String = predicate.op
	if operation != "sources" and id.is_empty():
		return false
	match operation:
		"evidence": return db.items.has(StringName(id)) and db.items[StringName(id)].category in InventoryService.KEYS
		"read": return id in READABLES
		"conversation": return id.contains("/")
		"flag": return id == "puzzle_solved"
		"choice": return CHOICES.has(id)
		"defeated":
			var world: Variant = db.get("map")
			if not world is Dictionary or not world.get("spawns") is Array:
				return false
			for spawn: Variant in world.spawns:
				if spawn is Dictionary and spawn.get("id") is String and spawn.id == id:
					return true
		"sources":
			if not predicate.get("ids") is Array or predicate.ids.is_empty():
				return false
			var seen: Dictionary = {}
			for source: Variant in predicate.ids:
				if not source is String or not source.begins_with("pickup/") or seen.has(source) or not db.containers.has(source.trim_prefix("pickup/")):
					return false
				seen[source] = true
			return true
	return false

## Call after SessionValidation's structural checks. Stale ACTIVE progress is valid
## between an acquisition transaction and reconciliation, but invented progress is not.
static func validate_snapshot(state: Dictionary, db: Node) -> MireTypes.ActionResult:
	for quest_id: StringName in db.quests:
		var definition: Dictionary = db.quests[quest_id].data
		var record: Dictionary = state.quests[String(quest_id)]
		if record.state not in STATES:
			return _invalid("Unknown quest state.")
		if record.state != "LOCKED" and not prerequisites_met(definition, state):
			return _invalid("Quest precedes its prerequisites: " + String(quest_id))
		var known: Dictionary = {}
		for objective: Dictionary in definition.objectives:
			known[objective.id] = true
			var progress: Variant = record.objectives.get(objective.id, 0)
			if not SessionValidation.whole(progress) or progress < 0 or progress > int(objective.count) or progress > count(objective.predicate, state):
				return _invalid("Invalid objective progress: " + String(objective.id))
			if record.state in ["LOCKED", "AVAILABLE"] and progress != 0:
				return _invalid("Unaccepted quest has progress.")
			if record.state == "COMPLETED" and (int(progress) != int(objective.count) or not satisfied(objective, state)):
				return _invalid("Completed quest lacks its objective: " + String(objective.id))
		for id: String in record.objectives:
			if not known.has(id):
				return _invalid("Unknown saved objective: " + id)
		if record.state == "READY" and not ready(definition, state):
			return _invalid("Ready quest lacks required evidence.")
		var receipt_id := String(completion_id(String(quest_id)))
		if state.transactions.has(receipt_id) != (record.state == "COMPLETED"):
			return _invalid("Quest completion and its receipt disagree.")
		if record.state == "COMPLETED":
			var payload: Dictionary = state.transactions[receipt_id].payload
			if payload.get("quest_id") != String(quest_id) or payload.get("crowns") != definition.rewards.crowns:
				return _invalid("Quest receipt does not describe the authored completion.")
			for item: String in definition.consume:
				if int(state.key_items.get(item, 0)) != 0 or not state.evidence.get(item, false):
					return _invalid("Completed hand-in lacks retained evidence or still carries its item.")
			for item: String in definition.rewards.items:
				if not state.evidence.get("reward/" + String(quest_id) + "/" + item, false):
					return _invalid("Completed quest lacks its item delivery.")
	for choice_id: String in CHOICES:
		var committed: bool = state.choices[choice_id] in CHOICES[choice_id]
		var quest_id: String = {"wren_terms": MQ04, "medicine_recipient": SQ06, "ending": MQ06}[choice_id]
		var completed: bool = state.quests[quest_id].state == "COMPLETED"
		if completed and not committed:
			return _invalid("Completed choice quest has no choice.")
		if committed:
			var receipt_id: String = "choice/wren_terms" if choice_id == "wren_terms" else String(completion_id(quest_id))
			var receipt_payload: Dictionary = state.transactions.get(receipt_id, {}).get("payload", {})
			if receipt_payload.get("choice_id") != choice_id or receipt_payload.get("value") != state.choices[choice_id]:
				return _invalid("Saved choice does not match its committed receipt.")
			if choice_id != "wren_terms" and not completed:
				return _invalid("Final choice was not committed with quest completion.")
			if choice_id == "wren_terms" and (state.quests[quest_id].state not in ["ACTIVE", "READY", "COMPLETED"] or not state.evidence.get("conversation/" + MQ04 + "/meet_wren", false) or not state.evidence.get("grain_ledger", false) or not state.transactions.has("choice/wren_terms")):
				return _invalid("Wren's testimony lacks its meeting, ledger or receipt.")
	var effect_quests := {"free_inn": "sq_02_a_warm_room", "shelter_lights": "sq_04_three_small_lights", "restored_badge": "sq_05_the_broken_badge"}
	for flag: String in effect_quests:
		if bool(state.flags.get(flag, false)) != (state.quests[effect_quests[flag]].state == "COMPLETED"):
			return _invalid("Quest consequence disagrees with completion: " + flag)
	var presented: bool = state.evidence.get("conversation/" + MQ05 + "/present_evidence", false)
	if bool(state.flags.get("undercroft_open", false)) != presented:
		return _invalid("Undercroft access lacks Ada's evidence handoff.")
	for step: String in CONVERSATIONS:
		if not state.evidence.get("conversation/" + step, false):
			continue
		var quest_id: String = step.get_slice("/", 0)
		if state.quests[quest_id].state not in ["ACTIVE", "READY", "COMPLETED"]:
			return _invalid("Story conversation precedes acceptance: " + step)
		for objective: Dictionary in db.quests[StringName(quest_id)].data.objectives:
			if objective.id == step:
				break
			if not satisfied(objective, state):
				return _invalid("Story conversation precedes required evidence: " + step)
	if presented and (int(state.key_items.get("orra_charter", 0)) != 1 or int(state.key_items.get("grain_ledger", 0)) != 1):
		return _invalid("Ada's handoff must retain charter and ledger.")
	var captain: Dictionary = state.world.get("captain_hall_captain_rusk_01", {})
	var captain_defeated: bool = captain.get("defeated") is bool and captain.defeated
	if captain_defeated and not state.evidence.get("conversation/" + MQ05 + "/challenge_rusk", false):
		return _invalid("Defeated Rusk lacks his accepted challenge.")
	if _fixed_source_acquired(state, "orra_charter", "charter_vault_coffer") and not state.flags.get("puzzle_solved", false):
		return _invalid("The charter was acquired before its vault puzzle was solved.")
	if _fixed_source_acquired(state, "rookwatch_seal", "captain_seal_chest") and not captain_defeated:
		return _invalid("The seal was acquired before Rusk was defeated.")
	if state.evidence.get("read/village_writ_table", false) and not state.evidence.get("conversation/" + MQ06 + "/discuss_resolution", false):
		return _invalid("Writ review precedes the final discussion.")
	if state.choices.ending != "none":
		return _validate_aftermath(state, db)
	return MireTypes.success()

static func _fixed_source_acquired(state: Dictionary, item_id: String, source_id: String) -> bool:
	if int(state.key_items.get(item_id, 0)) > 0 or state.evidence.get(item_id, false) or state.evidence.get("pickup/" + source_id, false):
		return true
	var source: Dictionary = state.world.get(source_id, {})
	return source.get("remaining") is Dictionary and not source.remaining.has(item_id)

static func _validate_aftermath(state: Dictionary, db: Node) -> MireTypes.ActionResult:
	var ending: String = state.choices.ending
	var expected := {
		"village_banner": {"style": "reed_green" if ending == "charter" else "silver" if ending == "warden" else "traveler"},
		"village_grain_tally": {"visible": ending == "charter"},
		"checkpoint_notice": {"text_id": "public_grain_tally" if ending == "charter" else "fixed_public_levy" if ending == "warden" else "traveler_sign"},
		"checkpoint_toll_bar": {"removed": ending == "free_road"},
		"checkpoint_banner": {"style": "reed_green" if ending == "charter" else "silver" if ending == "warden" else "removed"},
	}
	for id: String in expected:
		for field: String in expected[id]:
			if state.world.get(id, {}).get(field) != expected[id][field]:
				return _invalid("Ending aftermath does not match the resolution: " + id)
	for spawn: Dictionary in db.map.spawns:
		if spawn.group != "road_checkpoint":
			continue
		var guard: Dictionary = state.world.get(spawn.id, {})
		if guard.is_empty() or (ending == "free_road" and not guard.get("disabled", false)):
			return _invalid("Checkpoint withdrawal is incomplete.")
		if ending != "free_road" and not guard.get("defeated", false) and (guard.get("faction") != "neutral" or guard.get("disabled", false) or guard.get("role") != ("road_keeper" if ending == "charter" else "warden")):
			return _invalid("Surviving checkpoint guard lacks the chosen neutral role.")
	return MireTypes.success()

static func _invalid(message: String) -> MireTypes.ActionResult:
	return MireTypes.failure(&"invalid_state", StringName(message))
