extends RefCounted

const Service = preload("res://scripts/dialogue/dialogue_service.gd")
const Rules = preload("res://scripts/dialogue/dialogue_rules.gd")
const QuestFixture = preload("res://tests/unit/test_quests.gd")
const NPC_SCENE = preload("res://scenes/actors/npc.tscn")

class DialogueOwner extends Node:
	var dialogue: RefCounted

var t: SceneTree
var db: Node
var session: Node
var dialogue: RefCounted
var attempt: int = 0

func run(runner: SceneTree) -> void:
	t = runner
	db = t.root.get_node("ContentDB")
	session = t.root.get_node("GameSession")
	_reset()
	_content()
	_start_and_leave()
	_early_side_and_services()
	_remaining_side_turn_ins()
	for terms: String in ["amnesty", "restitution"]:
		_main_chain(terms)
	for recipient: String in ["camp", "village"]:
		_medicine(recipient)
	for ending: StringName in [&"charter", &"warden", &"free_road"]:
		_aftermath(ending)
	await _npc_adapter()
	await _npc_lifecycle()
	_reset()

func _reset() -> void:
	session.new_game()
	dialogue = Service.new(session)

func _id() -> StringName:
	attempt += 1
	return StringName("dialogue_fixture/" + str(attempt))

func _take(source: String, item: String) -> void:
	t.check(session.world_state.take_loot(StringName(source), StringName(item), 1, _id()).ok, "R33 dialogue fixture pickup " + source)

func _start(npc: String) -> Dictionary:
	var result: MireTypes.ActionResult = dialogue.start(StringName(npc))
	t.check(result.ok, "R32 opens " + npc + ": " + String(result.message_key))
	return result.payload.get("dialogue", {})

func _choose(id: String) -> MireTypes.ActionResult:
	var current: Dictionary = dialogue.view()
	var result: MireTypes.ActionResult = dialogue.choose(StringName(current.node_id), StringName(id))
	t.check(result.ok, "R32 chooses " + id + ": " + String(result.message_key))
	return result

func _has(view: Dictionary, id: String) -> bool:
	for choice: Dictionary in view.choices:
		if choice.id == id: return true
	return false

func _content() -> void:
	var errors: PackedStringArray = Rules.validate_definitions(db)
	t.check(errors.is_empty(), "R32 complete dialogue registries validate: " + "; ".join(errors))
	for speaker: StringName in db.dialogues:
		var definition: Dictionary = db.dialogues[speaker].data
		t.check(not definition.get("foundation_only", false), "R32 speaker has authored content " + String(speaker))
		for node: Dictionary in definition.nodes:
			t.check(not node.text.is_empty() and node.text.split(" ", false).size() <= 45, "R32 readable line " + String(speaker) + "/" + node.id)
	t.check(db.dialogues[&"captain_rusk"].data.combat_lines.half_health == "Very well. No more ceremony.", "R32 Rusk retains his canonical combat transition line")
	var canonical: Dictionary = db.dialogues[&"mara_venn"].data
	var mutations: Array[Dictionary] = [
		{"path": ["nodes", 0, "choices", 0, "next"], "value": "absent", "error": "Missing dialogue destination"},
		{"path": ["nodes", 0, "conditions"], "value": [{"op": "eval", "code": "grant_money()"}], "error": "dialogue condition"},
		{"path": ["nodes", 0, "conditions"], "value": [{"op": "quest_state", "id": "absent", "states": ["READY"]}], "error": "dialogue condition"},
		{"path": ["nodes", 0, "conditions"], "value": [{"op": "quest_state", "id": QuestPredicates.MQ06, "states": ["FINISHED"]}], "error": "dialogue condition"},
		{"path": ["nodes", 0, "conditions"], "value": [{"op": "objective_pending", "id": QuestPredicates.MQ06 + "/absent"}], "error": "dialogue condition"},
		{"path": ["nodes", 0, "choices", 0, "effect"], "value": {"op": "grant_crowns", "amount": 100}, "error": "dialogue effect"},
		{"path": ["nodes", 0, "choices", 0, "effect"], "value": {"op": "command", "command": "shop", "shop_id": []}, "error": "dialogue effect"},
		{"path": ["nodes", 0, "choices", 0, "effect"], "value": {"op": "activate", "quest_id": "sq_01_a_smiths_hand"}, "error": "dialogue effect"},
		{"path": ["nodes", 0, "choices", 0, "effect"], "value": {"op": "complete", "quest_id": "sq_01_a_smiths_hand"}, "error": "dialogue effect"},
		{"path": ["nodes", 0, "choices", 0, "effect"], "value": {"op": "choose", "choice_id": "medicine_recipient", "value": "village"}, "error": "dialogue effect"},
		{"path": ["nodes", 0, "text"], "value": "word ".repeat(46), "error": "exceeds 45 words"},
		{"path": ["nodes", 0, "text"], "value": "word\n\t".repeat(46), "error": "exceeds 45 words"},
		{"path": ["nodes", 1, "id"], "value": canonical.nodes[0].id, "error": "Duplicate or reserved dialogue node"},
	]
	for fixture: Dictionary in mutations:
		var changed: Dictionary = canonical.duplicate(true)
		var cursor: Variant = changed
		for index: int in fixture.path.size() - 1: cursor = cursor[fixture.path[index]]
		cursor[fixture.path.back()] = fixture.value
		t.check("; ".join(Rules.validate(changed, db)).contains(fixture.error), "R04 rejects authored dialogue defect: " + fixture.error)
	var changed: Dictionary = canonical.duplicate(true)
	changed.nodes.append({"id": "orphan", "text": "Nobody can reach this line.", "conditions": [], "choices": [], "priority": "ordinary", "greeting": false, "confirmation": false})
	t.check("; ".join(Rules.validate(changed, db)).contains("Unreachable dialogue node"), "R32 rejects inaccessible dialogue nodes")
	for path: Array in [["npc_id"], ["nodes"], ["topics"], ["nodes", 0, "priority"], ["nodes", 0, "greeting"], ["nodes", 0, "confirmation"], ["nodes", 0, "conditions"], ["nodes", 0, "choices", 0, "effect"], ["nodes", 0, "choices", 0, "next"]]:
		for value: Variant in [null, false, [], 7]:
			changed = canonical.duplicate(true)
			var cursor: Variant = changed
			for index: int in path.size() - 1: cursor = cursor[path[index]]
			cursor[path.back()] = value
			# An empty condition list and false metadata flags are valid authored values.
			if value is bool and path.back() in ["greeting", "confirmation"]: continue
			if value is Array and path.back() == "conditions": continue
			t.check(not Rules.validate(changed, db).is_empty(), "R04 malformed dialogue value rejected " + str(path) + ": " + str(value))

func _start_and_leave() -> void:
	for id: StringName in db.dialogues:
		var before: Dictionary = session.snapshot()
		var view: Dictionary = _start(String(id))
		t.check(not view.text.is_empty() and _has(view, "@leave") and view.max_visible_choices == 3, "R32 every speaker has text, Leave and scrollable choice contract")
		_choose("@leave")
		t.check(dialogue.view().is_empty() and session.state == before, "R34 starting and leaving does not commit " + String(id))
	var before: Dictionary = session.snapshot()
	t.check(not dialogue.start(&"missing").ok and not dialogue.choose(&"mara_venn/greeting", &"accept_mq01").ok and session.state == before, "R32 unknown speaker and closed conversation fail without effects")
	var view: Dictionary = _start("mara_venn")
	t.check(view.node_id.get_file() == "mq01_offer", "R32 available main quest outranks ordinary greeting")
	t.check(not dialogue.choose(&"mara_venn/greeting", &"accept_mq01").ok and session.state == before, "R34 stale node cannot accept a quest")
	_choose("accept_mq01")
	t.check(session.state.quests.mq_01_bread_and_iron.state == "ACTIVE", "R32 accepting dialogue uses quest activation")
	before = session.snapshot()
	t.check(not dialogue.choose(&"mara_venn/mq01_offer", &"accept_mq01").ok and session.state == before, "R34 duplicate acceptance callback cannot mutate state")
	view = dialogue.view()
	view.choices.clear()
	t.check(not dialogue.view().choices.is_empty(), "R32 view copies cannot alter authored choices")
	_start("sister_elian")
	t.check(not session.state.evidence.get("conversation/" + QuestPredicates.MQ03 + "/request_charter", false), "R33 early Elian contact never credits later charter request")

func _early_side_and_services() -> void:
	_reset()
	_take("kiln_hammer_crate", "smith_hammer")
	var view: Dictionary = _start("oswin_pike")
	t.check(view.node_id.get_file() == "sq01_offer" and _has(view, "open_shop"), "R32 side offer keeps smith shop reachable")
	_choose("accept_sq01")
	view = _start("oswin_pike")
	t.check(view.node_id.get_file() == "sq01_turn_in" and _has(view, "open_shop"), "R32 ready turn-in outranks active reminders without hiding shop")
	var before: Dictionary = session.snapshot()
	var shop: Dictionary = db.shops.oswin_pike
	db.shops.erase("oswin_pike")
	t.check(not dialogue.choose(&"oswin_pike/sq01_turn_in", &"open_shop").ok and session.state == before, "R34 stale shop target cannot dispatch an unavailable command")
	db.shops["oswin_pike"] = shop
	var routed: MireTypes.ActionResult = _choose("open_shop")
	t.check(routed.payload.ui_action == "shop" and routed.payload.command_pending and routed.payload.shop_id == "oswin_pike" and session.state == before, "R32 shop selection is an explicit request without invented purchase")
	_choose("complete_sq01")
	t.check(session.state.quests.sq_01_a_smiths_hand.state == "COMPLETED" and session.state.player.crowns == 24, "R34 early side pickup completes once through correct speaker")
	before = session.snapshot()
	t.check(not dialogue.choose(&"oswin_pike/sq01_turn_in", &"complete_sq01").ok and session.state == before, "R34 repeated turn-in callback cannot pay twice")
	_take("ferry_blanket_barrel", "ferry_blankets")
	view = _start("tamsin_reed")
	t.check(_has(view, "open_shop") and _has(view, "ask_rest_paid"), "R32 inn offer retains both shop and paid rest")
	_choose("accept_sq02")
	_choose("ask_rest_paid")
	before = session.snapshot()
	routed = _choose("request_rest_paid")
	t.check(routed.payload.ui_action == "rest" and routed.payload.command_pending and routed.payload.cost == 4 and session.state == before, "R32 paid rest is a routed request without charging or healing")
	_choose("ask_rest_paid")
	before = session.snapshot()
	t.check(session.quests.complete(&"sq_02_a_warm_room", _id()).ok, "R34 independent valid blanket hand-in changes rest price")
	var changed: Dictionary = session.snapshot()
	t.check(not dialogue.choose(&"tamsin_reed/rest_paid", &"request_rest_paid").ok and session.state == changed, "R34 stale paid rest choice is refreshed before dispatch")
	view = _start("tamsin_reed")
	t.check(_has(view, "open_shop") and _has(view, "ask_rest_free") and not _has(view, "ask_rest_paid"), "R32 free bed replaces paid option while shop remains")
	_choose("ask_rest_free")
	routed = _choose("request_rest_free")
	t.check(routed.payload.cost == 0 and session.state == changed, "R32 free rest request has current price and no direct state mutation")

func _remaining_side_turn_ins() -> void:
	_reset()
	for source: Array in [["shrine_ring_bowl", "hobb_ring"], ["watchtower_badge_locker", "ada_badge"], ["monastery_candle_01", "votive_candle"], ["monastery_candle_02", "votive_candle"], ["monastery_candle_03", "votive_candle"]]:
		_take(source[0], source[1])
	for assignment: Array in [["hobb_fenwick", "sq03"], ["sister_elian", "sq04"], ["ada_vey", "sq05"]]:
		_start(assignment[0])
		_choose("accept_" + assignment[1])
		var view: Dictionary = _start(assignment[0])
		t.check(view.node_id.get_file() == assignment[1] + "_turn_in", "R33 early side evidence reaches the correct speaker's turn-in")
		_choose("complete_" + assignment[1])
	t.check(session.state.flags.shelter_lights and session.state.flags.restored_badge and session.state.player.crowns == 65, "R30 ring, candles and badge pay their exact rewards and durable effects through dialogue")
	t.check(session.state.key_items.is_empty() and session.state.evidence.votive_candle and session.state.evidence.ada_badge and session.state.evidence.hobb_ring, "R33 side hand-ins retain permanent acquisition history")

func _main_chain(terms: String) -> void:
	_reset()
	for symbol: StringName in [&"reed", &"stone", &"flame"]: session.quests.ring_chime(symbol)
	for source: Array in [["charter_vault_coffer", "orra_charter"], ["watchtower_ledger_chest", "grain_ledger"], ["cart_coffer", "cart_medicine"], ["checkpoint_receipt_box", "toll_receipt"]]: _take(source[0], source[1])
	session.quests.read_document(&"toll_notice")
	for q: String in ["mq01", "mq02"]:
		_start("mara_venn")
		_choose("accept_" + q)
		_start("mara_venn")
		_choose("complete_" + q)
	_start("sister_elian")
	_choose("accept_mq03")
	_start("sister_elian")
	t.check(dialogue.view().node_id.get_file() == "mq03_request_charter", "R33 early charter still requires Elian's actual request")
	_choose("record_request_charter")
	_start("sister_elian")
	_choose("complete_mq03")
	t.check(session.state.evidence["conversation/" + QuestPredicates.MQ03 + "/attest_charter"], "R29 Elian's later attestation is recorded by turn-in")
	_start("wren_kest")
	_choose("accept_mq04")
	_start("wren_kest")
	_choose("record_meet_wren")
	var view: Dictionary = _start("wren_kest")
	t.check(view.node_id.get_file() == "wren_terms" and _has(view, "offer_sq06"), "R32 active main objective outranks side offer but keeps medicine quest reachable")
	var before: Dictionary = session.snapshot()
	_choose("review_" + terms)
	t.check(dialogue.view().confirmation and session.state == before, "R34 reviewing terms changes no quest state")
	_choose("cancel_terms")
	t.check(session.state == before and not dialogue.view().confirmation, "R34 cancelling terms is inert")
	_choose("review_" + terms)
	_choose("confirm_" + terms)
	t.check(session.state.choices.wren_terms == terms, "R34 explicit terms confirmation commits " + terms)
	before = session.snapshot()
	t.check(not dialogue.choose(StringName("wren_kest/confirm_" + terms), StringName("confirm_" + terms)).ok and session.state == before, "R34 duplicate terms confirmation cannot commit again")
	_start("wren_kest")
	t.check(not _has(dialogue.view(), "turn_in_mq04") and session.state.quests[QuestPredicates.MQ04].state == "READY", "R32 Wren cannot receive Mara's report")
	_start("mara_venn")
	_choose("complete_mq04")
	_start("ada_vey")
	_choose("accept_mq05")
	_start("ada_vey")
	_choose("record_present_evidence")
	t.check(session.state.flags.undercroft_open and dialogue.view().text.contains("door is open"), "R29 Ada announces access only after committing evidence")
	before = session.snapshot()
	_start("captain_rusk")
	_choose("@leave")
	t.check(session.state == before, "R32 leaving Rusk does not challenge him")
	_start("captain_rusk")
	var challenge: MireTypes.ActionResult = _choose("challenge_rusk")
	t.check(challenge.payload.ui_action == "challenge_rusk" and challenge.payload.command_pending and dialogue.view().is_empty(), "R32 explicit challenge records conversation and requests world combat")
	before = session.snapshot()
	_start("captain_rusk")
	challenge = _choose("challenge_rusk")
	t.check(challenge.payload.command_pending and challenge.payload.outcome.replayed and session.state == before, "R32 living Rusk can be challenged again after runtime recovery without repeating story effects")
	_start("captain_rusk")
	session.world_state.mark_defeated(&"captain_hall_captain_rusk_01")
	before = session.snapshot()
	t.check(not dialogue.choose(&"captain_rusk/challenge", &"challenge_rusk").ok and not dialogue.start(&"captain_rusk").ok and session.state == before, "R32 defeated Rusk rejects stale and new challenges")
	_take("captain_seal_chest", "rookwatch_seal")
	_start("ada_vey")
	_choose("complete_mq05")
	_start("mara_venn")
	_choose("accept_mq06")
	_start("mara_venn")
	_choose("record_discuss_resolution")
	t.check(session.state.choices.ending == "none" and not session.state.evidence.get("read/village_writ_table", false), "R29 Mara directs the player to the writ without silently reviewing or choosing")
	t.check(QuestPredicates.validate_snapshot(session.snapshot(), db).ok, "R34 complete dialogue-driven pre-ending chain obeys semantic invariants")

func _medicine(recipient: String) -> void:
	_reset()
	_take("raider_medicine_cache", "camp_medicine")
	_start("wren_kest")
	_choose("accept_sq06")
	var npc: String = "wren_kest" if recipient == "camp" else "mara_venn"
	var view: Dictionary = _start(npc)
	t.check(view.node_id.get_file() == "medicine_" + recipient, "R32 medicine turn-in has priority over new main or ordinary greeting")
	if recipient == "village": t.check(_has(view, "offer_mq01"), "R32 medicine delivery does not hide Mara's unrelated main offer")
	var before: Dictionary = session.snapshot()
	_choose("review_medicine_" + recipient)
	t.check(dialogue.view().text.contains("This decides who receives the medicine.") and session.state == before, "R34 medicine preview names its irreversible consequence")
	_choose("cancel_medicine")
	t.check(session.state == before, "R34 cancelling medicine delivery preserves item and reward")
	_choose("review_medicine_" + recipient)
	_choose("@leave")
	t.check(session.state == before, "R34 leaving a confirmation preserves all unconfirmed effects")
	_start(npc)
	_choose("review_medicine_" + recipient)
	_choose("confirm_medicine_" + recipient)
	t.check(session.state.choices.medicine_recipient == recipient and session.state.player.crowns == 22 and not session.state.key_items.has("camp_medicine"), "R34 medicine consumption, recipient and ten crowns commit together")
	before = session.snapshot()
	view = _start("mara_venn" if recipient == "camp" else "wren_kest")
	t.check(not _has(view, "deliver_medicine_village") and not _has(view, "deliver_medicine_camp") and session.state == before, "R34 other recipient remains usable without a second delivery")
	# A valid independent recipient commit invalidates an already displayed confirmation.
	_reset()
	_take("raider_medicine_cache", "camp_medicine")
	_start("wren_kest")
	_choose("accept_sq06")
	_start("wren_kest")
	_choose("review_medicine_camp")
	t.check(session.quests.choose(&"medicine_recipient", &"village", _id()).ok, "R34 independent recipient fixture uses the real domain transaction")
	before = session.snapshot()
	t.check(not dialogue.choose(&"wren_kest/confirm_medicine_camp", &"confirm_medicine_camp").ok and session.state == before, "R34 stale material confirmation cannot override the committed recipient")

func _aftermath(ending: StringName) -> void:
	t.check(QuestFixture.ending_checkpoint(session, ending, &"amnesty").ok, "R32 legitimate ending fixture " + String(ending))
	dialogue = Service.new(session)
	for npc: String in ["mara_venn", "ada_vey", "oswin_pike", "tamsin_reed", "sister_elian", "hobb_fenwick", "wren_kest"]:
		var view: Dictionary = _start(npc)
		var topic_id: String = "ask_aftermath_" + (String(ending) if npc in ["mara_venn", "ada_vey"] else "road")
		var target: String = topic_id.trim_prefix("ask_")
		t.check(view.node_id.get_file() == target or _has(view, topic_id), "R32 ending reaction remains accessible despite side offers: " + npc)
		if view.node_id.get_file() != target: _choose(topic_id)
		t.check(not dialogue.view().text.is_empty(), "R32 authored " + String(ending) + " aftermath for " + npc)
		if npc in ["oswin_pike", "tamsin_reed"]: t.check(_has(dialogue.view(), "open_shop"), "R32 aftermath preserves shop access")
		if npc == "tamsin_reed": t.check(_has(dialogue.view(), "ask_rest_paid"), "R32 aftermath preserves inn rest")
	var before: Dictionary = session.snapshot()
	_start("oswin_pike")
	_choose("ask_aftermath_road")
	var old_node: StringName = StringName(dialogue.view().node_id)
	_start("tamsin_reed")
	_choose("ask_aftermath_road")
	t.check(not dialogue.choose(old_node, &"open_shop").ok and session.state == before, "R34 stale callback from another speaker cannot reuse an identically named node/choice")
	var shop: MireTypes.ActionResult = _choose("open_shop")
	t.check(shop.payload.shop_id == "tamsin_reed" and shop.payload.command_pending, "R32 current speaker still routes to the correct shop")
	_start("oswin_pike")
	_choose("accept_sq01")
	t.check(session.state.quests.sq_01_a_smiths_hand.state == "ACTIVE" and session.state.choices == before.choices, "R30 side quests remain acceptable after " + String(ending))

func _npc_adapter() -> void:
	_reset()
	var owner := DialogueOwner.new()
	owner.dialogue = dialogue
	t.root.add_child(owner)
	var listeners: int = t.root.get_node("EventBus").get_signal_connection_list("quest_updated").size()
	for id: StringName in [&"mara_venn", &"oswin_pike", &"tamsin_reed", &"sister_elian", &"hobb_fenwick", &"ada_vey", &"wren_kest"]:
		var actor: StaticBody3D = NPC_SCENE.instantiate()
		t.root.add_child(actor)
		t.check(actor.configure(owner, id).ok and actor.name_label.text == db.dialogues[id].data.speaker_name, "R32 real civilian adapter uses canonical speaker name " + String(id))
		t.check(actor.collision_layer == MireTypes.NEUTRAL and actor.find_children("*", "CombatHurtbox", true, false).is_empty(), "R32 civilian has a neutral body and no hostile hurtbox")
		var result: MireTypes.ActionResult = actor.interaction.interact(&"player", &"talk")
		t.check(result.ok and result.payload.dialogue.npc_id == String(id), "R32 actual NPC interaction opens the real dialogue service")
		if id == &"mara_venn":
			_choose("accept_mq01")
			_take("cart_coffer", "cart_medicine")
			t.check(actor.quest_marker.visible and actor.quest_marker.text == "?", "R32 committed evidence updates real NPC turn-in marker")
			_start("mara_venn")
			_choose("complete_mq01")
			t.check(actor.quest_marker.text == "!", "R32 completed hand-in exposes the next quest marker")
		actor.queue_free()
		await t.process_frame
	var captain: StaticBody3D = NPC_SCENE.instantiate()
	t.root.add_child(captain)
	t.check(not captain.configure(owner, &"captain_rusk").ok and captain.collision_layer == 0 and captain.model == null, "R32 captain cannot become an invulnerable civilian placeholder")
	captain.queue_free()
	owner.queue_free()
	await t.process_frame
	t.check(t.root.get_node("EventBus").get_signal_connection_list("quest_updated").size() == listeners, "R40 freeing NPCs releases their event listeners")

func _npc_lifecycle() -> void:
	_reset()
	var owner := DialogueOwner.new()
	owner.dialogue = dialogue
	t.root.add_child(owner)
	var bus: Node = t.root.get_node("EventBus")
	var baseline: Array[int] = _listeners(bus)
	var live: Array[int] = [baseline[0] + 1, baseline[1] + 1, baseline[2] + 1]
	var actor: StaticBody3D = NPC_SCENE.instantiate()
	t.root.add_child(actor)
	t.check(_listeners(bus) == baseline and not actor.activate().ok, "R40 unconfigured NPC has no live listeners")
	t.check(actor.configure(owner, &"mara_venn", false).ok and actor.model != null and actor.quest_marker.text == "!", "R40 staged NPC builds art and an initial view")
	t.check(_listeners(bus) == baseline and not actor.is_processing() and not actor.interaction.enabled, "R40 prepared NPC has no live bindings, animation or interaction")
	session.quests.activate(&"mq_01_bread_and_iron")
	_take("cart_coffer", "cart_medicine")
	bus.choice_committed.emit(&"medicine_recipient", &"camp")
	bus.session_restored.emit()
	t.check(actor.quest_marker.text == "!" and _listeners(bus) == baseline, "R40 staged actor ignores live quest, choice and restore notifications")
	var before: Dictionary = session.snapshot()
	t.check(not actor.interaction.interact(&"player", &"talk").ok and session.state == before, "R40 staged NPC cannot start dialogue")
	t.check(actor.activate().ok and actor.activate().ok and _listeners(bus) == live and actor.quest_marker.text == "?", "R40 explicit activation binds once and refreshes current committed state")
	actor.deactivate()
	actor.deactivate()
	t.check(_listeners(bus) == baseline and not actor.is_processing() and not actor.interaction.enabled, "R40 repeated deactivation removes every live binding")
	session.quests.complete(&"mq_01_bread_and_iron", _id())
	t.check(actor.quest_marker.text == "?" and not actor.interaction.interact(&"player", &"talk").ok, "R40 inactive NPC ignores later quest changes and callbacks")
	t.check(actor.activate().ok and actor.quest_marker.text == "!" and _listeners(bus) == live, "R40 reactivation shows the new quest without duplicate listeners")
	var children: int = actor.get_child_count()
	t.root.remove_child(actor)
	t.check(_listeners(bus) == baseline and not actor.activate().ok, "R40 detaching NPC releases live listeners")
	t.root.add_child(actor)
	t.check(_listeners(bus) == baseline and not actor.interaction.enabled and actor.get_child_count() == children, "R40 re-entered NPC preserves geometry and awaits explicit activation")
	t.check(actor.activate().ok and _listeners(bus) == live, "R40 explicit re-entry activation restores one listener set")
	actor.queue_free()
	await t.process_frame
	t.check(_listeners(bus) == baseline, "R40 active NPC cleanup restores all listener counts")
	owner.queue_free()
	await t.process_frame

func _listeners(bus: Node) -> Array[int]:
	return [bus.get_signal_connection_list("quest_updated").size(), bus.get_signal_connection_list("choice_committed").size(), bus.get_signal_connection_list("session_restored").size()]
