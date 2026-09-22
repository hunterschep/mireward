class_name QuestService
extends RefCounted
## Quest mutations stage together with inventory, currency and world consequences.

signal autosave_requested(reason: StringName)

const DOCUMENTS := {
	"southern_sign": ["Southern sign", "BRACKENFORD: Work, shelter, lawful measures. ROOKWATCH: Toll payable on demand. Someone scratched out 'lawful'."],
	"toll_notice": ["Toll notice", "By emergency authority: grain levy doubled until further notice. A newer date has been painted over an older one."],
	"toll_receipt": ["Toll receipt", "Six sacks received. Two entered. Difference retained for discretionary provision. R."],
	"abbey_inscription": ["Abbey inscription", "Reed for the traveler. Stone for the shelter. Flame for the watch. Offer them in the order of mercy."],
	"orra_charter": ["Saint Orra's charter", "The road shall be kept for passage, and the granary for want. Neither office shall become a private purse."],
	"grain_ledger": ["Grain ledger", "Village levy: forty sacks. Garrison issue: eleven. Northern sale: twenty-nine. Names repeat beneath several missing carts."],
	"ferry_ledger": ["Ferry ledger", "Paid: flour, two hens, one roof repair. Owed: nothing worth mentioning."],
	"captains_order": ["Captain's order", "No receipts to be issued for reserve transfers. Existing records to be surrendered."],
	"broken_bell_plaque": ["Broken bell plaque", "For those who keep a light when no one is expected."],
	"village_writ_table": ["The Last Toll", "Restore the village charter: public grain tally, neutral road keepers, shop purchases 15% cheaper. Bind the wardens to an oath: fixed public levy, neutral wardens, shop purchases 5% cheaper. Break the toll authority: checkpoint soldiers withdraw, toll bar removed, ordinary shop prices. Confirming one resolution is permanent."],
}
const ENDINGS := {
	"charter": "The road belonged to no single hand. Its keepers were named in the square, its grain counted in daylight. Greyfen became no paradise. It became a place where an answer could be demanded.",
	"warden": "The toll remained, but the ledger opened. Ada put her name beneath every order. Some called it a better cage. Others called it a road they could finally travel.",
	"free_road": "No seal claimed the road. Carts passed beneath an empty arch, and every village learned how much work freedom could be. For a season, at least, no one paid to go home.",
}
var session: Node
var db: Node
var tracked_quest: StringName = &""
var puzzle_progress: int = 0

func _init(owner: Node) -> void:
	session = owner
	db = owner.get_node("/root/ContentDB")

func reset_runtime() -> void:
	puzzle_progress = 0
	tracked_quest = &""

func activate(quest_id: StringName) -> MireTypes.ActionResult:
	if not db.quests.has(quest_id):
		return _failure(&"unknown_quest", "That quest does not exist.")
	var result: MireTypes.ActionResult = session.transactions.run(StringName("quest/" + String(quest_id) + "/activate"), func(candidate: Dictionary) -> MireTypes.ActionResult:
		var definition: Dictionary = db.quests[quest_id].data
		var record: Dictionary = candidate.quests[String(quest_id)]
		if not QuestPredicates.prerequisites_met(definition, candidate) or record.state == "LOCKED":
			return _failure(&"locked", "Complete the earlier quest first.")
		if record.state != "AVAILABLE":
			return _failure(&"already_active", "That quest has already been accepted.")
		record.state = "ACTIVE"
		var staged := MireTypes.success({"quest_id": String(quest_id)})
		_reconcile_candidate(candidate, staged)
		_event_once(staged, &"quest_updated", [quest_id])
		return staged
	)
	if result.ok and tracked_quest.is_empty():
		tracked_quest = quest_id
	return result

## Repeated evidence notifications do not create receipts or publish events.
func reconcile() -> void:
	var preview: Dictionary = session.snapshot()
	var staged := MireTypes.success()
	_reconcile_candidate(preview, staged)
	if preview.quests == session.state.quests:
		return
	var identity := StringName("quest/reconcile/" + JSON.stringify(preview.quests).sha256_text())
	session.transactions.run(identity, func(candidate: Dictionary) -> MireTypes.ActionResult:
		var result := MireTypes.success()
		_reconcile_candidate(candidate, result)
		return result
	)

func complete(quest_id: StringName, transaction_id: StringName) -> MireTypes.ActionResult:
	if transaction_id.is_empty():
		return _failure(&"invalid_transaction", "The turn-in needs a transaction ID.")
	if not db.quests.has(quest_id):
		return _failure(&"unknown_quest", "That quest does not exist.")
	if String(quest_id) in [QuestPredicates.MQ06, QuestPredicates.SQ06]:
		return _failure(&"choice_required", "Review and confirm the material choice first.")
	var result: MireTypes.ActionResult = session.transactions.run(QuestPredicates.completion_id(String(quest_id)), func(candidate: Dictionary) -> MireTypes.ActionResult:
		return _stage_complete(candidate, String(quest_id))
	)
	_request_save(result, &"quest_completed")
	return result

func choose(choice_id: StringName, value: StringName, transaction_id: StringName) -> MireTypes.ActionResult:
	var id := String(choice_id)
	var selected := String(value)
	if transaction_id.is_empty():
		return _failure(&"invalid_transaction", "The choice needs a transaction ID.")
	if not QuestPredicates.CHOICES.has(id) or selected not in QuestPredicates.CHOICES[id]:
		return _failure(&"invalid_choice", "Choose one of the available resolutions.")
	var previous: String = session.state.choices[id]
	if previous in QuestPredicates.CHOICES[id] and previous != selected:
		return _failure(&"choice_locked", "That choice has already been made.")
	var quest_id: String = {"wren_terms": QuestPredicates.MQ04, "medicine_recipient": QuestPredicates.SQ06, "ending": QuestPredicates.MQ06}[id]
	var receipt: StringName = &"choice/wren_terms" if id == "wren_terms" else QuestPredicates.completion_id(quest_id)
	var result: MireTypes.ActionResult = session.transactions.run(receipt, func(candidate: Dictionary) -> MireTypes.ActionResult:
		if id == "ending" and (session.danger or session.action_locked or session.travelling):
			return _failure(&"unsafe", "Resolve danger and finish the current action before deciding the road's future.")
		if candidate.quests[quest_id].state not in ["ACTIVE", "READY"]:
			return _failure(&"not_active", "Accept and advance this quest first.")
		var definition: Dictionary = db.quests[StringName(quest_id)].data
		var objective_id: String = quest_id + {"wren_terms": "/choose_wren_terms", "medicine_recipient": "/deliver_medicine", "ending": "/confirm_ending"}[id]
		if not _earlier_steps_met(definition, objective_id, candidate):
			return _failure(&"not_ready", "Complete the preceding objective before making this choice.")
		candidate.choices[id] = selected
		var staged := MireTypes.success({"choice_id": id, "value": selected})
		if id == "ending":
			_stage_aftermath(candidate, selected)
		if id != "wren_terms":
			staged = _stage_complete(candidate, quest_id)
			if not staged.ok:
				return staged
			staged.payload.merge({"choice_id": id, "value": selected})
		_reconcile_candidate(candidate, staged)
		staged.event(&"choice_committed", [choice_id, value])
		return staged
	)
	_request_save(result, &"choice_committed")
	return result

## Only named story steps can be recorded. Completing a quest owns its final return.
func record_conversation(npc_id: StringName, step_id: StringName) -> MireTypes.ActionResult:
	var step := String(step_id)
	if QuestPredicates.CONVERSATIONS.get(step) != String(npc_id):
		return _failure(&"invalid_step", "That character cannot advance this conversation step.")
	var quest_id: String = step.get_slice("/", 0)
	if step == QuestPredicates.MQ05 + "/challenge_rusk" and session.state.world.get("captain_hall_captain_rusk_01", {}).get("defeated", false):
		return _failure(&"not_available", "The captain has already been defeated.")
	return session.transactions.run(StringName("quest/step/" + step), func(candidate: Dictionary) -> MireTypes.ActionResult:
		if candidate.quests[quest_id].state not in ["ACTIVE", "READY"]:
			return _failure(&"not_active", "Accept the relevant quest first.")
		if not _earlier_steps_met(db.quests[StringName(quest_id)].data, step, candidate):
			return _failure(&"not_ready", "Complete the preceding objective first.")
		if step == QuestPredicates.MQ05 + "/present_evidence":
			if int(candidate.key_items.get("orra_charter", 0)) != 1 or int(candidate.key_items.get("grain_ledger", 0)) != 1:
				return _failure(&"not_owned", "Bring both the charter and the grain account to Ada.")
			candidate.flags.undercroft_open = true
		if step == QuestPredicates.MQ05 + "/challenge_rusk" and (not candidate.flags.undercroft_open or candidate.world.get("captain_hall_captain_rusk_01", {}).get("defeated", false)):
			return _failure(&"not_available", "The captain cannot be challenged now.")
		var evidence := "conversation/" + step
		candidate.evidence[evidence] = true
		var result := MireTypes.success({"step_id": step, "npc_id": String(npc_id)}).event(&"evidence_acquired", [StringName(evidence)])
		_reconcile_candidate(candidate, result)
		return result
	)

func read_document(document_id: StringName) -> MireTypes.ActionResult:
	var id := String(document_id)
	if not DOCUMENTS.has(id):
		return _failure(&"unknown_document", "That document is not authored.")
	# Reopening a reviewed writ still validates access, and never activates MQ06.
	if id == "village_writ_table" and (session.state.quests[QuestPredicates.MQ06].state not in ["ACTIVE", "READY", "COMPLETED"] or not session.state.evidence.get("conversation/" + QuestPredicates.MQ06 + "/discuss_resolution", false)):
		return _failure(&"not_ready", "Speak to Mara about The Last Toll first.")
	return session.transactions.run(StringName("read/" + id), func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.evidence["read/" + id] = true
		var result := MireTypes.success(document_view(document_id)).event(&"evidence_acquired", [StringName("read/" + id)])
		_reconcile_candidate(candidate, result)
		return result
	)

func ring_chime(symbol: StringName) -> MireTypes.ActionResult:
	var sequence := [&"reed", &"stone", &"flame"]
	if symbol not in sequence:
		return _failure(&"invalid_chime", "Choose reed, stone, or flame.")
	if session.state.flags.puzzle_solved:
		return MireTypes.success({"solved": true, "progress": 3, "already_solved": true})
	if symbol != sequence[puzzle_progress]:
		puzzle_progress = 0
		return MireTypes.success({"solved": false, "progress": 0, "reset": true})
	if puzzle_progress < 2:
		puzzle_progress += 1
		return MireTypes.success({"solved": false, "progress": puzzle_progress, "reset": false})
	var result: MireTypes.ActionResult = session.transactions.run(&"puzzle/crypt_bell_puzzle/solved", func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.flags.puzzle_solved = true
		var solved := MireTypes.success({"solved": true, "progress": 3}).event(&"evidence_acquired", [&"puzzle/crypt_bell_puzzle"])
		_reconcile_candidate(candidate, solved)
		return solved
	)
	if result.ok:
		puzzle_progress = 0
	return result

func document_view(document_id: StringName) -> Dictionary:
	var id := String(document_id)
	if not DOCUMENTS.has(id):
		return {}
	return {"document_id": id, "title": DOCUMENTS[id][0], "text": DOCUMENTS[id][1]}

func quest_view(quest_id: StringName) -> Dictionary:
	if not db.quests.has(quest_id):
		return {}
	var definition: Dictionary = db.quests[quest_id].data
	var record: Dictionary = session.state.quests[String(quest_id)]
	var view := {"quest_id": String(quest_id), "name": definition.name, "state": record.state, "giver_id": definition.giver_id, "turn_in_npc_id": definition.turn_in_npc_id, "objectives": [], "next_objective": {}, "turn_in_available": record.state == "READY"}
	for objective: Dictionary in definition.objectives:
		var row: Dictionary = objective.duplicate(true)
		row["progress"] = clampi(QuestPredicates.count(objective.predicate, session.state), 0, int(objective.count)) if record.state in ["ACTIVE", "READY", "COMPLETED"] else 0
		row["completed"] = row.progress == int(row.count)
		view.objectives.append(row)
		if view.next_objective.is_empty() and not row.completed and record.state in ["ACTIVE", "READY"]:
			view.next_objective = row.duplicate(true)
	return view

func journal_view() -> Dictionary:
	var view := {"active": [], "completed": [], "documents": [], "tracked": tracked_view()}
	for id: StringName in db.quests:
		var row := quest_view(id)
		if row.state in ["ACTIVE", "READY"]:
			view.active.append(row)
		elif row.state == "COMPLETED":
			view.completed.append(row)
	for id: String in DOCUMENTS:
		if session.state.evidence.get("read/" + id, false) or session.state.evidence.get(id, false):
			view.documents.append(document_view(StringName(id)))
	return view

func track(quest_id: StringName) -> MireTypes.ActionResult:
	if not db.quests.has(quest_id) or session.state.quests[String(quest_id)].state not in ["ACTIVE", "READY"]:
		return _failure(&"not_active", "Only an accepted unfinished quest can be tracked.")
	tracked_quest = quest_id
	return MireTypes.success(tracked_view())

func tracked_view() -> Dictionary:
	var id: StringName = tracked_quest
	if id.is_empty() or session.state.quests.get(String(id), {}).get("state") not in ["ACTIVE", "READY"]:
		id = &""
		for candidate: StringName in db.quests:
			if session.state.quests[String(candidate)].state in ["ACTIVE", "READY"]:
				id = candidate
				break
	if id.is_empty():
		for candidate: StringName in db.quests:
			if not String(candidate).begins_with("mq_") or session.state.quests[String(candidate)].state != "AVAILABLE":
				continue
			var available: Dictionary = db.quests[candidate].data
			var invitation := {"id": String(candidate) + "/accept", "label": "Speak to " + _speaker_name(available.giver_id) + " about " + String(available.name), "target_id": available.giver_id, "hint_target_id": available.giver_id, "scene_id": available.giver_scene_id, "location": available.giver_location, "progress": 0, "count": 1, "completed": false, "acceptance": true}
			return {"quest_id": String(candidate), "name": available.name, "objective": invitation}
		return {}
	var view := quest_view(id)
	var objective: Dictionary = view.next_objective
	if not objective.is_empty():
		objective["hint_target_id"] = objective.get("portal_id", objective.target_id) if session.state.player.scene_id != objective.scene_id and objective.scene_id != "exterior" else objective.target_id
	return {"quest_id": String(id), "name": view.name, "objective": objective}

func epilogue_view() -> Array[String]:
	var ending: String = session.state.choices.ending
	if not ENDINGS.has(ending):
		return []
	var terms: String = "The deserters signed their names and took work where they could find it." if session.state.choices.wren_terms == "amnesty" else "Wren's first repayment arrived on a cart that carried no armed escort."
	var medicine: String = {"unset": "The sick in the valley still waited on small mercies.", "camp": "Under the tarps, the fevers broke.", "village": "At the village well, another list of names grew shorter."}[session.state.choices.medicine_recipient]
	return [ENDINGS[ending], terms + " " + medicine, "You came with a borrowed sword. What you owed the valley was now a thing you had chosen."]

func _stage_complete(candidate: Dictionary, quest_id: String) -> MireTypes.ActionResult:
	var definition: Dictionary = db.quests[StringName(quest_id)].data
	var record: Dictionary = candidate.quests[quest_id]
	if record.state not in ["ACTIVE", "READY"] or not QuestPredicates.prerequisites_met(definition, candidate) or not QuestPredicates.ready(definition, candidate):
		return _failure(&"not_ready", "Complete the required objectives before turning in this quest.")
	var final_objective: Dictionary = definition.objectives.back()
	var result := MireTypes.success({"quest_id": quest_id, "crowns": int(definition.rewards.crowns), "deliveries": [], "transaction_id": String(QuestPredicates.completion_id(quest_id))})
	if final_objective.predicate.op == "choice" and not QuestPredicates.satisfied(final_objective, candidate):
		return _failure(&"choice_required", "Confirm a recipient or resolution first.")
	for item: String in definition.consume:
		var removed: MireTypes.ActionResult = session.inventory.stage_remove_key(candidate, StringName(item), int(definition.consume[item]))
		if not removed.ok:
			return removed
		result.events.append_array(removed.events)
	candidate.player.crowns = int(candidate.player.crowns) + int(definition.rewards.crowns)
	if int(definition.rewards.crowns) > 0:
		result.event(&"currency_changed")
	for item: String in definition.rewards.items:
		var delivered: MireTypes.ActionResult = session.inventory.stage_reward(candidate, StringName(item), int(definition.rewards.items[item]), StringName(quest_id + "/" + item))
		if not delivered.ok:
			return delivered
		result.events.append_array(delivered.events)
		result.payload.deliveries.append(delivered.payload.duplicate(true))
	for effect: Dictionary in definition.completion_effects:
		if effect.get("op") != "flag" or effect.get("id") not in QuestPredicates.EFFECT_FLAGS or effect.get("value") != true:
			return _failure(&"invalid_effect", "This quest contains an unsupported completion effect.")
		candidate.flags[String(effect.id)] = true
	if final_objective.predicate.op == "conversation":
		var evidence: String = "conversation/" + String(final_objective.predicate.id)
		candidate.evidence[evidence] = true
		result.event(&"evidence_acquired", [StringName(evidence)])
	record.state = "COMPLETED"
	_reconcile_candidate(candidate, result)
	_event_once(result, &"quest_updated", [StringName(quest_id)])
	return result

func _reconcile_candidate(candidate: Dictionary, result: MireTypes.ActionResult) -> void:
	for id: StringName in db.quests:
		var definition: Dictionary = db.quests[id].data
		var record: Dictionary = candidate.quests[String(id)]
		var previous: Dictionary = record.duplicate(true)
		if record.state == "LOCKED" and QuestPredicates.prerequisites_met(definition, candidate):
			record.state = "AVAILABLE"
		if record.state in ["ACTIVE", "READY", "COMPLETED"]:
			for objective: Dictionary in definition.objectives:
				var observed: int = clampi(QuestPredicates.count(objective.predicate, candidate), 0, int(objective.count))
				if not record.objectives.has(objective.id) or observed > int(record.objectives[objective.id]):
					record.objectives[String(objective.id)] = observed
			if record.state == "ACTIVE" and QuestPredicates.ready(definition, candidate):
				record.state = "READY"
		if record != previous:
			_event_once(result, &"quest_updated", [id])

func _earlier_steps_met(definition: Dictionary, objective_id: String, candidate: Dictionary) -> bool:
	for objective: Dictionary in definition.objectives:
		if objective.id == objective_id:
			return true
		if not QuestPredicates.satisfied(objective, candidate):
			return false
	return false

func _stage_aftermath(candidate: Dictionary, ending: String) -> void:
	candidate.world["village_banner"] = {"style": "reed_green" if ending == "charter" else "silver" if ending == "warden" else "traveler"}
	candidate.world["village_grain_tally"] = {"visible": ending == "charter"}
	candidate.world["checkpoint_notice"] = {"text_id": "public_grain_tally" if ending == "charter" else "fixed_public_levy" if ending == "warden" else "traveler_sign"}
	candidate.world["checkpoint_toll_bar"] = {"removed": ending == "free_road"}
	candidate.world["checkpoint_banner"] = {"style": "reed_green" if ending == "charter" else "silver" if ending == "warden" else "removed"}
	for spawn: Dictionary in db.map.spawns:
		if spawn.group != "road_checkpoint":
			continue
		var id: String = spawn.id
		var record: Dictionary = candidate.world.get(id, {}).duplicate(true)
		if record.is_empty():
			record = {"kind": "corpse", "archetype": String(spawn.archetype), "defeated": false, "disabled": false, "opened": false, "remaining": {}, "crowns_remaining": int(db.enemies[StringName(spawn.archetype)].data.loot_crowns)}
		if ending == "free_road":
			record.disabled = true
		elif not record.get("defeated", false):
			record["faction"] = "neutral"
			record["role"] = "road_keeper" if ending == "charter" else "warden"
		candidate.world[id] = record

func _request_save(result: MireTypes.ActionResult, reason: StringName) -> void:
	if result.ok and not result.payload.get("replayed", false):
		autosave_requested.emit(reason)

func _event_once(result: MireTypes.ActionResult, name: StringName, args: Array) -> void:
	for event: Dictionary in result.events:
		if event.name == name and event.args == args:
			return
	result.event(name, args)

func _failure(code: StringName, message: String) -> MireTypes.ActionResult:
	return MireTypes.failure(code, StringName(message))

func _speaker_name(npc_id: String) -> String:
	return {"mara_venn": "Mara", "sister_elian": "Elian", "wren_kest": "Wren", "ada_vey": "Ada"}.get(npc_id, npc_id.replace("_", " ").capitalize())
