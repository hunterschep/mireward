extends RefCounted

const MAIN := ["mq_01_bread_and_iron", "mq_02_the_kings_due", "mq_03_a_bell_without_rope", "mq_04_names_in_the_ledger", "mq_05_a_debt_in_stone", "mq_06_the_last_toll"]
const SIDES := ["sq_01_a_smiths_hand", "sq_02_a_warm_room", "sq_03_what_the_reeds_keep", "sq_04_three_small_lights", "sq_05_the_broken_badge", "sq_06_no_clean_hands"]
var session: Node
var db: Node
var quests: QuestService
var t: SceneTree
var attempt: int = 0

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	db = t.root.get_node("ContentDB")
	_reset()
	t.check(QuestPredicates.validate_definitions(db).is_empty(), "R28 all twelve complete definitions validate")
	_definition_failures()
	_malformed_definition_types()
	_initial_and_failures()
	_puzzle_and_early_pickups()
	_chain("amnesty", "charter")
	_side_quests("camp")
	_chain("restitution", "warden")
	_side_quests("village")
	_chain("amnesty", "free_road")
	_overflow_and_rollback()
	_invalid_snapshots()
	_gated_source_snapshots()
	for ending: StringName in [&"none", &"charter", &"warden", &"free_road"]:
		t.check(ending_checkpoint(session, ending).ok and session.state.choices.ending == String(ending), "R35 reusable genuine campaign fixture " + String(ending))
	_reset()

func _reset() -> void:
	session.new_game()
	quests = QuestService.new(session)

func _id(label: String) -> StringName:
	attempt += 1
	return StringName("test_quests/" + label + "/" + str(attempt))

func _take(source: String, item: String) -> void:
	var result: MireTypes.ActionResult = session.world_state.take_loot(StringName(source), StringName(item), 1, _id("take"))
	t.check(result.ok, "R33 fixed pickup " + source)
	quests.reconcile()

func _accept(id: String) -> void:
	t.check(quests.activate(StringName(id)).ok, "R28 accept " + id)

func _complete(id: String) -> void:
	var result := quests.complete(StringName(id), _id("complete"))
	t.check(result.ok and session.state.quests[id].state == "COMPLETED", "R34 complete " + id)
	t.check(QuestPredicates.validate_snapshot(session.snapshot(), db).ok, "R34 completed snapshot validates " + id)

func _talk(id: String, npc: String, step: String) -> void:
	t.check(quests.record_conversation(StringName(npc), StringName(id + "/" + step)).ok, "R29 story conversation " + step)

func _initial_and_failures() -> void:
	var before: Dictionary = session.snapshot()
	t.check(quests.journal_view().active.is_empty(), "R28 side quests available without appearing in active journal")
	t.check(quests.tracked_view().objective.target_id == "mara_venn" and quests.tracked_view().objective.acceptance, "R28 new game gives an actionable invitation to Mara without activating a quest")
	t.check(session.state.quests[MAIN[0]].state == "AVAILABLE" and session.state.quests[MAIN[1]].state == "LOCKED", "R28 initial main quest states")
	t.check(not quests.activate(StringName(MAIN[1])).ok, "R28 prerequisites block activation")
	t.check(not quests.complete(StringName(MAIN[0]), _id("early")).ok, "R34 unavailable quest cannot complete")
	t.check(not quests.choose(&"ending", &"charter", _id("early")).ok, "R35 ending cannot bypass main campaign")
	t.check(not quests.choose(&"ending", &"unknown", _id("invalid")).ok, "R34 unknown choice enum rejected")
	t.check(not quests.read_document(&"village_writ_table").ok, "R29 writ cannot silently activate final quest")
	t.check(not quests.record_conversation(&"sister_elian", StringName(MAIN[2] + "/request_charter")).ok, "R33 early meeting does not perform later charter conversation")
	t.check(not quests.read_document(&"untrusted_expression()").ok, "R28 unknown predicate input rejected")
	t.check(session.state == before, "R34 all failed early actions leave state and receipts unchanged")
	quests.reconcile()
	quests.reconcile()
	t.check(session.state == before, "R28 no-op reconciliation does not add receipts")
	_accept(MAIN[0])
	var view := quests.quest_view(StringName(MAIN[0]))
	t.check(view.next_objective.id == MAIN[0] + "/acquire_cart_medicine" and not view.next_objective.location.is_empty(), "R28 accepted quest has a concrete next step and location")
	view.objectives.clear()
	t.check(quests.quest_view(StringName(MAIN[0])).objectives.size() == 2, "R28 journal views cannot mutate definitions")
	before = session.snapshot()
	t.check(not quests.complete(StringName(MAIN[0]), &"").ok and session.state == before, "R34 empty request ID changes nothing")

func _solve() -> void:
	for chime: StringName in [&"reed", &"stone", &"flame"]:
		t.check(quests.ring_chime(chime).ok, "R31 bell sequence " + String(chime))

func _puzzle_and_early_pickups() -> void:
	_reset()
	quests.ring_chime(&"reed")
	t.check(quests.puzzle_progress == 1 and not session.state.flags.puzzle_solved, "R31 first chime advances transient marker")
	var saved: Dictionary = session.snapshot()
	t.check(quests.ring_chime(&"flame").payload.reset and quests.puzzle_progress == 0, "R31 incorrect chime resets progress")
	t.check(session.state == saved, "R31 partial and incorrect puzzle inputs do not mutate permanent state")
	quests.ring_chime(&"reed")
	quests = QuestService.new(session)
	t.check(quests.puzzle_progress == 0, "R31 recreated puzzle begins with zero partial progress")
	_solve()
	_take("charter_vault_coffer", "orra_charter")
	_take("watchtower_ledger_chest", "grain_ledger")
	_take("kiln_hammer_crate", "smith_hammer")
	_take("watchtower_badge_locker", "ada_badge")
	for number: int in range(1, 4):
		_take("monastery_candle_0%d" % number, "votive_candle")
	saved = session.snapshot()
	var count: int = saved.transactions.size()
	quests.ring_chime(&"flame")
	quests.reconcile()
	quests.reconcile()
	t.check(session.state.transactions.size() == count and session.state == saved, "R31 solved puzzle and duplicate events do not issue receipts or rewards")
	for id: String in [SIDES[0], SIDES[3], SIDES[4]]:
		_accept(id)
		t.check(session.state.quests[id].state == "READY", "R33 early pickup reconciles on acceptance " + id)
		_complete(id)
	t.check(session.state.flags.shelter_lights and session.state.flags.restored_badge, "R30 early side turn-ins persist physical consequences")
	t.check(not session.state.key_items.has("votive_candle") and session.state.evidence.votive_candle, "R33 candle hand-in retains permanent acquisition")
	for number: int in range(1, 4):
		t.check(session.state.evidence["pickup/monastery_candle_0%d" % number], "R33 distinct candle source history retained")
	saved = session.snapshot()
	t.check(not session.world_state.take_loot(&"monastery_candle_01", &"votive_candle", 1, _id("duplicate_candle")).ok and session.state == saved, "R30 revisiting a candle cannot add another count")
	t.check(session.state.evidence.orra_charter and session.state.evidence.grain_ledger, "R33 side turn-ins never consume main evidence")
	_reset()
	_accept(SIDES[3])
	_take("monastery_candle_01", "votive_candle")
	t.check(quests.quest_view(StringName(SIDES[3])).objectives[0].progress == 1 and session.state.quests[SIDES[3]].state == "ACTIVE", "R30 one source is exactly one of three candles")
	saved = session.snapshot()
	t.check(not quests.complete(StringName(SIDES[3]), _id("one_candle")).ok and session.state == saved, "R30 one candle cannot complete the quest")

func _chain(terms: String, ending: String) -> void:
	_reset()
	_solve()
	_take("charter_vault_coffer", "orra_charter")
	_take("watchtower_ledger_chest", "grain_ledger")
	quests.read_document(&"toll_notice")
	_take("checkpoint_receipt_box", "toll_receipt")
	_take("cart_coffer", "cart_medicine")
	_accept(MAIN[0])
	t.check(session.state.quests[MAIN[0]].state == "READY", "R29 return to Mara ready from early coffer acquisition")
	var commits: Array[Dictionary] = []
	var on_currency := func() -> void: commits.append(session.snapshot())
	var bus: Node = session.get_node("/root/EventBus")
	bus.currency_changed.connect(on_currency)
	_complete(MAIN[0])
	bus.currency_changed.disconnect(on_currency)
	t.check(commits.size() == 1 and commits[0].quests[MAIN[0]].state == "COMPLETED" and not commits[0].key_items.has("cart_medicine"), "R34 notifications observe the full committed turn-in")
	t.check(session.state.player.crowns == 30 and not session.state.key_items.has("cart_medicine") and session.state.evidence.cart_medicine, "R29 MQ01 pays 18 and consumes only carried medicine")
	t.check(quests.tracked_view().quest_id == MAIN[1] and quests.tracked_view().objective.target_id == "mara_venn", "R28 next main quest points to its giver after turn-in")
	var after: Dictionary = session.snapshot()
	var duplicate := quests.complete(StringName(MAIN[0]), _id("double_submit"))
	t.check(duplicate.ok and duplicate.payload.replayed and session.state == after, "R34 two turn-in attempts pay once under canonical receipt")
	_accept(MAIN[1])
	_complete(MAIN[1])
	t.check(session.state.player.crowns == 52 and session.state.key_items.toll_receipt == 1, "R29 MQ02 pays 22 and retains receipt")
	_accept(MAIN[2])
	t.check(session.state.quests[MAIN[2]].state == "ACTIVE", "R33 early charter does not skip Elian's request")
	_talk(MAIN[2], "sister_elian", "request_charter")
	t.check(session.state.quests[MAIN[2]].state == "READY" and not session.state.evidence.get("conversation/" + MAIN[2] + "/attest_charter", false), "R29 return ready is distinct from later attestation")
	_complete(MAIN[2])
	t.check(session.state.evidence["conversation/" + MAIN[2] + "/attest_charter"] and session.state.player.crowns == 80, "R29 Elian attestation and 28 crowns commit together")
	_accept(MAIN[3])
	after = session.snapshot()
	t.check(not quests.choose(&"wren_terms", StringName(terms), _id("before_meeting")).ok and session.state == after, "R34 early ledger alone cannot choose Wren's terms")
	_talk(MAIN[3], "wren_kest", "meet_wren")
	t.check(quests.choose(&"wren_terms", StringName(terms), _id("terms")).ok, "R34 explicit Wren terms " + terms)
	after = session.snapshot()
	t.check(quests.choose(&"wren_terms", StringName(terms), _id("same_terms")).payload.replayed and session.state == after, "R34 repeated same Wren choice is inert")
	t.check(not quests.choose(&"wren_terms", &"restitution" if terms == "amnesty" else &"amnesty", _id("change_terms")).ok and session.state == after, "R34 Wren choice is permanently locked")
	_complete(MAIN[3])
	t.check(session.state.player.crowns == 110 and session.state.key_items.grain_ledger == 1, "R29 MQ04 pays 30 and retains ledger for either terms")
	_accept(MAIN[4])
	_talk(MAIN[4], "ada_vey", "present_evidence")
	t.check(session.state.flags.undercroft_open and session.state.key_items.orra_charter == 1, "R29 Ada opens undercroft while retaining main documents")
	t.check(quests.track(StringName(MAIN[4])).ok and quests.tracked_view().objective.hint_target_id == "undercroft_door", "R28 indoor objective points to entrance from exterior")
	_talk(MAIN[4], "captain_rusk", "challenge_rusk")
	t.check(quests.record_conversation(&"captain_rusk", StringName(MAIN[4] + "/challenge_rusk")).payload.replayed, "R29 explicit re-challenge can restart runtime fight after recovery")
	t.check(QuestPredicates.validate_snapshot(session.snapshot(), db).ok, "R38 accepted challenge with a living captain remains a valid recovery/load state")
	t.check(session.world_state.mark_defeated(&"captain_hall_captain_rusk_01").ok, "R29 boss defeat uses authored persistent spawn")
	t.check(QuestPredicates.validate_snapshot(session.snapshot(), db).ok, "R38 defeated captain remains saveable before collecting his fixed seal")
	t.check(not quests.record_conversation(&"captain_rusk", StringName(MAIN[4] + "/challenge_rusk")).ok, "R29 defeated captain cannot be challenged by stale dialogue")
	_take("captain_seal_chest", "rookwatch_seal")
	if ending == "free_road":
		session.inventory.try_add(&"arming_sword", 16 - session.state.inventory.size(), _id("fill_for_watchblade"))
	_complete(MAIN[4])
	t.check(session.state.player.crowns == 150 and (session.state.pending_delivery.has(MAIN[4] + "/watchblade") if ending == "free_road" else _count("watchblade") == 1), "R29 MQ05 pays 40 and delivers or queues one Watchblade")
	after = session.snapshot()
	t.check(not quests.read_document(&"village_writ_table").ok and session.state == after, "R29 newly available MQ06 still requires deliberate acceptance")
	_accept(MAIN[5])
	_talk(MAIN[5], "mara_venn", "discuss_resolution")
	after = session.snapshot()
	t.check(not quests.choose(&"ending", StringName(ending), _id("unreviewed")).ok and session.state == after, "R35 ending requires writ review")
	t.check(quests.read_document(&"village_writ_table").ok and session.state.choices.ending == "none", "R35 review preserves unconfirmed choice")
	session.world_state.mark_defeated(&"road_checkpoint_levy_spearman_01")
	session.world_state.take_crowns(&"road_checkpoint_levy_spearman_01", _id("checkpoint_loot"))
	var dead: Dictionary = session.world_state.get_entity_state(&"road_checkpoint_levy_spearman_01")
	after = session.snapshot()
	for flag: String in ["danger", "action_locked", "travelling"]:
		session.set(flag, true)
		t.check(not quests.choose(&"ending", StringName(ending), _id("unsafe")).ok and session.state == after, "R35 unsafe ending refused: " + flag)
		session.set(flag, false)
	var save_requests: Array[StringName] = []
	quests.autosave_requested.connect(func(reason: StringName) -> void: save_requests.append(reason))
	t.check(quests.choose(&"ending", StringName(ending), _id("ending")).ok, "R35 choose ending " + ending)
	t.check(session.state.quests[MAIN[5]].state == "COMPLETED" and session.state.choices.ending == ending and session.state.player.crowns == after.player.crowns, "R35 ending and campaign complete atomically without reward")
	t.check(save_requests == [&"choice_committed"], "R35 exactly one save request after ending commit")
	var corpse: Dictionary = session.world_state.get_entity_state(&"road_checkpoint_levy_spearman_01")
	t.check(corpse.defeated and corpse.crowns_remaining == 0 and (ending == "free_road" or corpse == dead), "R35 defeated checkpoint guard and collected loot remain dead/empty")
	for number: int in [2, 3]:
		var guard: Dictionary = session.world_state.get_entity_state(StringName("road_checkpoint_levy_spearman_0%d" % number))
		t.check(guard.disabled if ending == "free_road" else guard.faction == "neutral", "R35 surviving checkpoint aftermath " + ending)
	t.check(session.state.world.checkpoint_toll_bar.removed == (ending == "free_road"), "R35 toll bar reflects chosen ending")
	t.check(QuestPredicates.validate_snapshot(session.snapshot(), db).ok, "R35 completed ending passes semantic validation")
	var damaged: Dictionary = session.snapshot()
	damaged.world.checkpoint_banner.style = "red"
	t.check(not QuestPredicates.validate_snapshot(damaged, db).ok, "R35 snapshot rejects ending with wrong persistent banner")
	damaged = session.snapshot()
	damaged.world.road_checkpoint_levy_spearman_02.disabled = false
	damaged.world.road_checkpoint_levy_spearman_02["faction"] = "hostile"
	t.check(not QuestPredicates.validate_snapshot(damaged, db).ok, "R35 snapshot rejects hostile or enabled ending checkpoint")
	after = session.snapshot()
	t.check(quests.choose(&"ending", StringName(ending), _id("ending_again")).payload.replayed and session.state == after and save_requests.size() == 1, "R35 replay cannot repeat ending changes or save request")
	t.check(not quests.choose(&"ending", &"warden" if ending != "warden" else &"charter", _id("ending_change")).ok and session.state == after, "R35 ending is immutable")
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(after))
	t.check(session.restore(encoded).ok, "R37 completed campaign survives JSON reload")
	quests = QuestService.new(session)
	quests.reconcile()
	t.check(session.state == encoded and quests.epilogue_view().size() == 3, "R36 reload reconciles without rewards or forced epilogue")
	t.check(quests.epilogue_view()[1].contains("still waited"), "R36 epilogue includes incomplete medicine quest")

func _side_quests(recipient: String) -> void:
	var start_crowns: int = int(session.state.player.crowns)
	var sources := [["kiln_hammer_crate", "smith_hammer"], ["ferry_blanket_barrel", "ferry_blankets"], ["shrine_ring_bowl", "hobb_ring"], ["monastery_candle_01", "votive_candle"], ["monastery_candle_02", "votive_candle"], ["monastery_candle_03", "votive_candle"], ["watchtower_badge_locker", "ada_badge"], ["raider_medicine_cache", "camp_medicine"]]
	for source: Array in sources:
		_take(source[0], source[1])
	for id: String in SIDES:
		_accept(id)
		if id != SIDES[5]:
			_complete(id)
	t.check(session.state.flags.free_inn and session.state.flags.shelter_lights and session.state.flags.restored_badge, "R30 all side physical consequences persisted after ending")
	t.check(_count("arming_sword") == 1 and _count("kite_shield") == 1 and _count("bandage") == 6, "R30 exact equipment and bandage rewards")
	var before: Dictionary = session.snapshot()
	t.check(not quests.complete(StringName(SIDES[5]), _id("no_recipient")).ok and session.state == before, "R34 medicine requires explicit recipient")
	t.check(quests.choose(&"medicine_recipient", StringName(recipient), _id("medicine")).ok, "R34 medicine delivered to " + recipient)
	t.check(session.state.player.crowns == start_crowns + 85 and not session.state.key_items.has("camp_medicine") and session.state.evidence.camp_medicine, "R30 six sides pay exact 85 crowns and retain consumed medicine evidence")
	before = session.snapshot()
	t.check(not quests.choose(&"medicine_recipient", &"village" if recipient == "camp" else &"camp", _id("other_recipient")).ok and session.state == before, "R34 other NPC cannot receive medicine or pay twice")
	t.check(quests.choose(&"medicine_recipient", StringName(recipient), _id("same_recipient")).payload.replayed and session.state == before, "R34 same recipient replay does not pay twice")
	t.check(quests.epilogue_view()[1].contains("fevers broke" if recipient == "camp" else "list of names grew shorter"), "R36 journal replay reflects later medicine completion")
	t.check(QuestPredicates.validate_snapshot(before, db).ok and quests.journal_view().completed.size() == 12, "R30 all twelve completed records and journal retained")
	t.check(session.state == before, "R36 epilogue replay is a pure view")

func _overflow_and_rollback() -> void:
	_reset()
	session.inventory.try_add(&"arming_sword", 11, _id("fill"))
	_take("kiln_hammer_crate", "smith_hammer")
	_accept(SIDES[0])
	_complete(SIDES[0])
	var delivery: String = SIDES[0] + "/arming_sword"
	t.check(session.state.pending_delivery.has(delivery) and session.state.player.crowns == 24 and not session.state.key_items.has("smith_hammer"), "R25 full inventory stages currency, consumption and pending reward atomically")
	var before: Dictionary = session.snapshot()
	t.check(not session.inventory.claim_pending(StringName(delivery)).ok and session.state == before, "R25 full inventory reward claim fails without mutation")
	session.transactions.run(_id("free_slot"), func(candidate: Dictionary) -> MireTypes.ActionResult: return session.inventory.stage_remove(candidate, &"stack_5", 1))
	t.check(session.inventory.claim_pending(StringName(delivery)).ok and not session.state.pending_delivery.has(delivery) and _count("arming_sword") == 12, "R25 pending reward can be claimed once after freeing space")
	t.check(session.inventory.claim_pending(StringName(delivery)).payload.replayed and _count("arming_sword") == 12, "R25 pending claim replay does not duplicate gear")
	_reset()
	_take("kiln_hammer_crate", "smith_hammer")
	_accept(SIDES[0])
	before = session.snapshot()
	var definition: Dictionary = db.quests[StringName(SIDES[0])].data
	definition.completion_effects.append({"op": "unsafe_unknown_effect"})
	t.check(not quests.complete(StringName(SIDES[0]), _id("invalid_effect")).ok and session.state == before, "R34 failed late effect rolls back currency, reward, consumption and receipt")
	definition.completion_effects.clear()
	_complete(SIDES[0])
	_take("raider_medicine_cache", "camp_medicine")
	_accept(SIDES[5])
	before = session.snapshot()
	definition = db.quests[StringName(SIDES[5])].data
	definition.completion_effects.append({"op": "unsafe_unknown_effect"})
	t.check(not quests.choose(&"medicine_recipient", &"camp", _id("failed_medicine")).ok and session.state == before, "R34 late medicine failure rolls back recipient, gold and consumed item")
	definition.completion_effects.clear()
	t.check(quests.choose(&"medicine_recipient", &"village", _id("retry_medicine")).ok, "R34 failed choice leaves the other recipient genuinely available")

func _invalid_snapshots() -> void:
	var good: Dictionary = session.snapshot()
	var bad: Dictionary = good.duplicate(true)
	bad.quests[SIDES[0]].objectives[SIDES[0] + "/acquire_smith_hammer"] = 2
	t.check(not QuestPredicates.validate_snapshot(bad, db).ok, "R28 snapshot rejects out-of-bounds objective counter")
	bad = good.duplicate(true)
	bad.quests[SIDES[0]].objectives.clear()
	t.check(not QuestPredicates.validate_snapshot(bad, db).ok, "R28 snapshot rejects completed quest with missing objective records")
	bad = good.duplicate(true)
	bad.quests[SIDES[0]].objectives["invented"] = 1
	t.check(not QuestPredicates.validate_snapshot(bad, db).ok, "R28 snapshot rejects unknown objective identity")
	bad = good.duplicate(true)
	bad.evidence.erase("smith_hammer")
	t.check(not QuestPredicates.validate_snapshot(bad, db).ok, "R33 snapshot rejects completed hand-in without evidence")
	bad = good.duplicate(true)
	bad.flags.free_inn = true
	t.check(not QuestPredicates.validate_snapshot(bad, db).ok, "R30 snapshot rejects free inn before blanket turn-in")
	bad = good.duplicate(true)
	bad.transactions.erase(String(QuestPredicates.completion_id(SIDES[0])))
	t.check(not QuestPredicates.validate_snapshot(bad, db).ok, "R34 snapshot rejects completed quest without receipt")
	bad = good.duplicate(true)
	bad.quests[SIDES[0]].state = "READY"
	t.check(not QuestPredicates.validate_snapshot(bad, db).ok, "R34 snapshot rejects completion receipt without completion")
	bad = good.duplicate(true)
	bad.choices.ending = "charter"
	t.check(not QuestPredicates.validate_snapshot(bad, db).ok, "R35 snapshot rejects ending without completed campaign")
	bad = good.duplicate(true)
	bad.quests[MAIN[2]].state = "ACTIVE"
	t.check(not QuestPredicates.validate_snapshot(bad, db).ok, "R28 snapshot rejects active quest before prerequisite")

func _count(item: String) -> int:
	var count: int = 0
	for stack: Dictionary in session.state.inventory:
		if stack.item_id == item:
			count += int(stack.quantity)
	return count

## Reusable domain fixture for prices, saves and aftermath. No story flags are forged.
## ending="none" stops at the reviewed writ; otherwise commits the selected ending.
static func ending_checkpoint(owner: Node, ending: StringName = &"none", terms: StringName = &"amnesty") -> MireTypes.ActionResult:
	if String(ending) not in ["none", "charter", "warden", "free_road"] or String(terms) not in ["amnesty", "restitution"]:
		return MireTypes.failure(&"invalid_fixture", &"Choose a canonical ending and Wren terms.")
	owner.new_game()
	var service := QuestService.new(owner)
	var world: WorldStateService = owner.world_state
	var actions: Array[Callable] = [
		func() -> MireTypes.ActionResult: return service.ring_chime(&"reed"),
		func() -> MireTypes.ActionResult: return service.ring_chime(&"stone"),
		func() -> MireTypes.ActionResult: return service.ring_chime(&"flame"),
		func() -> MireTypes.ActionResult: return world.take_loot(&"charter_vault_coffer", &"orra_charter", 1, &"fixture/charter"),
		func() -> MireTypes.ActionResult: return world.take_loot(&"watchtower_ledger_chest", &"grain_ledger", 1, &"fixture/ledger"),
		func() -> MireTypes.ActionResult: return world.take_loot(&"cart_coffer", &"cart_medicine", 1, &"fixture/cart"),
		func() -> MireTypes.ActionResult: return service.activate(StringName(MAIN[0])),
		func() -> MireTypes.ActionResult: return service.complete(StringName(MAIN[0]), &"fixture/mq01"),
		func() -> MireTypes.ActionResult: return service.activate(StringName(MAIN[1])),
		func() -> MireTypes.ActionResult: return service.read_document(&"toll_notice"),
		func() -> MireTypes.ActionResult: return world.take_loot(&"checkpoint_receipt_box", &"toll_receipt", 1, &"fixture/receipt"),
		func() -> MireTypes.ActionResult: return service.complete(StringName(MAIN[1]), &"fixture/mq02"),
		func() -> MireTypes.ActionResult: return service.activate(StringName(MAIN[2])),
		func() -> MireTypes.ActionResult: return service.record_conversation(&"sister_elian", StringName(MAIN[2] + "/request_charter")),
		func() -> MireTypes.ActionResult: return service.complete(StringName(MAIN[2]), &"fixture/mq03"),
		func() -> MireTypes.ActionResult: return service.activate(StringName(MAIN[3])),
		func() -> MireTypes.ActionResult: return service.record_conversation(&"wren_kest", StringName(MAIN[3] + "/meet_wren")),
		func() -> MireTypes.ActionResult: return service.choose(&"wren_terms", terms, &"fixture/terms"),
		func() -> MireTypes.ActionResult: return service.complete(StringName(MAIN[3]), &"fixture/mq04"),
		func() -> MireTypes.ActionResult: return service.activate(StringName(MAIN[4])),
		func() -> MireTypes.ActionResult: return service.record_conversation(&"ada_vey", StringName(MAIN[4] + "/present_evidence")),
		func() -> MireTypes.ActionResult: return service.record_conversation(&"captain_rusk", StringName(MAIN[4] + "/challenge_rusk")),
		func() -> MireTypes.ActionResult: return world.mark_defeated(&"captain_hall_captain_rusk_01"),
		func() -> MireTypes.ActionResult: return world.take_loot(&"captain_seal_chest", &"rookwatch_seal", 1, &"fixture/seal"),
		func() -> MireTypes.ActionResult: return service.complete(StringName(MAIN[4]), &"fixture/mq05"),
		func() -> MireTypes.ActionResult: return service.activate(StringName(MAIN[5])),
		func() -> MireTypes.ActionResult: return service.record_conversation(&"mara_venn", StringName(MAIN[5] + "/discuss_resolution")),
		func() -> MireTypes.ActionResult: return service.read_document(&"village_writ_table"),
	]
	if ending != &"none":
		actions.append(func() -> MireTypes.ActionResult: return service.choose(&"ending", ending, &"fixture/ending"))
	for action: Callable in actions:
		var result: MireTypes.ActionResult = action.call()
		if not result.ok:
			return result
	service.reconcile()
	return QuestPredicates.validate_snapshot(owner.snapshot(), owner.get_node("/root/ContentDB"))

func _gated_source_snapshots() -> void:
	_reset()
	for source: Array in [["charter_vault_coffer", "orra_charter"], ["captain_seal_chest", "rookwatch_seal"]]:
		for signal_kind: String in ["held", "evidence", "pickup", "depleted"]:
			var malformed: Dictionary = session.snapshot()
			match signal_kind:
				"held": malformed.key_items[source[1]] = 1
				"evidence": malformed.evidence[source[1]] = true
				"pickup": malformed.evidence["pickup/" + source[0]] = true
				"depleted":
					var record: Dictionary = session.world_state.get_entity_state(StringName(source[0]))
					record.remaining.clear()
					malformed.world[source[0]] = record
			t.check(SessionValidation.validate(malformed, db).ok, "R38 gated-source fixture is structurally valid: " + source[0] + "/" + signal_kind)
			var checked := QuestPredicates.validate_snapshot(malformed, db)
			t.check(not checked.ok and String(checked.message_key).contains("acquired before"), "R38 rejects gated source without its prerequisite: " + source[0] + "/" + signal_kind)
		var untouched: Dictionary = session.snapshot()
		untouched.world[source[0]] = session.world_state.get_entity_state(StringName(source[0]))
		t.check(QuestPredicates.validate_snapshot(untouched, db).ok, "R38 an authored but uncollected source is not mistaken for acquisition")
	# This structurally valid record previously passed the save semantics and made
	# the later mandatory challenge impossible. Runtime boss gating is owned by T20.
	t.check(session.world_state.mark_defeated(&"captain_hall_captain_rusk_01").ok, "R38 construct the formerly accepted unchallenged-defeat record")
	var premature_defeat: Dictionary = session.snapshot()
	t.check(SessionValidation.validate(premature_defeat, db).ok and not QuestPredicates.validate_snapshot(premature_defeat, db).ok, "R38 save semantics reject Rusk defeated before an accepted challenge")
	_reset()
	t.check(session.restore(premature_defeat).ok, "R38 reproduce the pre-gate raw restore of the structurally valid candidate")
	for symbol: StringName in [&"reed", &"stone", &"flame"]:
		t.check(quests.ring_chime(symbol).ok, "R38 softlock fixture solves the real puzzle")
	for source: Array in [["charter_vault_coffer", "orra_charter"], ["watchtower_ledger_chest", "grain_ledger"], ["cart_coffer", "cart_medicine"], ["checkpoint_receipt_box", "toll_receipt"]]:
		_take(source[0], source[1])
	t.check(quests.read_document(&"toll_notice").ok, "R38 softlock fixture reads toll evidence")
	for quest: String in [MAIN[0], MAIN[1]]:
		_accept(quest)
		t.check(quests.complete(StringName(quest), _id("softlock")).ok, "R38 otherwise ordinary progress toward the blocked challenge: " + quest)
	_accept(MAIN[2])
	_talk(MAIN[2], "sister_elian", "request_charter")
	t.check(quests.complete(StringName(MAIN[2]), _id("softlock")).ok, "R38 softlock fixture completes Elian's attestation")
	_accept(MAIN[3])
	_talk(MAIN[3], "wren_kest", "meet_wren")
	t.check(quests.choose(&"wren_terms", &"amnesty", _id("softlock")).ok and quests.complete(StringName(MAIN[3]), _id("softlock")).ok, "R38 softlock fixture records legitimate terms and report")
	_accept(MAIN[4])
	_talk(MAIN[4], "ada_vey", "present_evidence")
	var challenged := quests.record_conversation(&"captain_rusk", StringName(MAIN[4] + "/challenge_rusk"))
	t.check(not challenged.ok and challenged.code == &"not_available" and quests.quest_view(StringName(MAIN[4])).next_objective.id == MAIN[4] + "/challenge_rusk", "R38 premature defeat would leave MQ05 requiring a permanently refused challenge")
	var blocked := QuestPredicates.validate_snapshot(session.snapshot(), db)
	t.check(not blocked.ok and String(blocked.message_key).contains("Defeated Rusk"), "R38 later acceptance and Ada's handoff cannot legitimize the unchallenged defeat")
	_reset()
	_solve()
	_take("charter_vault_coffer", "orra_charter")
	for source: Array in [["watchtower_ledger_chest", "grain_ledger"], ["watchtower_badge_locker", "ada_badge"], ["kiln_hammer_crate", "smith_hammer"], ["monastery_candle_01", "votive_candle"], ["monastery_candle_02", "votive_candle"], ["monastery_candle_03", "votive_candle"]]:
		_take(source[0], source[1])
	t.check(session.state.quests[MAIN[2]].state == "LOCKED" and QuestPredicates.validate_snapshot(session.snapshot(), db).ok, "R33 solved-early charter and ordinary early ledger, badge, hammer and candle pickups remain valid")

func _definition_failures() -> void:
	var definition: Dictionary = db.quests[StringName(SIDES[3])].data
	var objective: Dictionary = definition.objectives[0]
	var original: Dictionary = objective.duplicate(true)
	objective.predicate.ids[1] = objective.predicate.ids[0]
	t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R28 content rejects repeated candle source")
	definition.objectives[0] = original.duplicate(true)
	definition.objectives[0].predicate.ids[0] = "pickup/kiln_hammer_crate"
	t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R28 content rejects counting another quest's pickup as a candle")
	definition.objectives[0] = original.duplicate(true)
	definition.objectives[0].predicate.op = "eval"
	t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R28 content rejects non-whitelisted predicate")
	definition.objectives[0] = original.duplicate(true)
	definition.objectives[0].predicate.ids = 5
	t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R28 malformed source list returns validation errors")
	definition.objectives[0] = original.duplicate(true)
	definition.objectives[0].predicate["id"] = []
	t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R28 malformed predicate ID returns validation errors")
	definition.objectives[0] = original
	t.check(QuestPredicates.validate_definitions(db).is_empty(), "R28 restored canonical content validates")

func _malformed_definition_types() -> void:
	var definition: Dictionary = db.quests[StringName(MAIN[2])].data
	var original: Dictionary = definition.duplicate(true)
	var invalid_values: Array = [null, true, [], {}, INF, NAN]
	for value: Variant in [null, [], {}, INF, NAN]:
		definition["foundation_only"] = value
		t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed reservation marker returns diagnostics")
		definition.erase("foundation_only")
	for field: String in ["name", "giver_id", "giver_location", "giver_scene_id", "turn_in_npc_id"]:
		for value: Variant in invalid_values:
			definition[field] = value
			t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed quest metadata returns diagnostics: " + field + "/" + type_string(typeof(value)))
			definition[field] = original[field]
	for field: String in ["prerequisites", "objectives", "completion_effects"]:
		for value: Variant in [null, true, {}, INF, NAN]:
			definition[field] = value
			t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed quest array returns diagnostics: " + field)
			definition[field] = original[field].duplicate(true)
	for field: String in ["rewards", "consume"]:
		for value: Variant in [null, true, [], INF, NAN]:
			definition[field] = value
			t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed quest dictionary returns diagnostics: " + field)
			definition[field] = original[field].duplicate(true)
	for value: Variant in invalid_values:
		definition.objectives[0] = value
		t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed objective row returns diagnostics")
		definition.objectives[0] = original.objectives[0].duplicate(true)
	for value: Variant in invalid_values:
		definition.objectives = original.objectives.duplicate(true)
		definition.objectives.append(value)
		t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed final objective cannot cause a dictionary comparison error")
		definition.objectives = original.objectives.duplicate(true)
	for field: String in ["id", "label", "target_id", "location", "scene_id", "portal_id", "npc_id", "item_id", "alternative_target_id"]:
		for value: Variant in invalid_values:
			definition.objectives[0][field] = value
			t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed objective field returns diagnostics: " + field + "/" + type_string(typeof(value)))
			definition.objectives[0] = original.objectives[0].duplicate(true)
	for field: String in ["count", "turn_in", "predicate"]:
		for value: Variant in invalid_values:
			definition.objectives[0][field] = value
			t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed objective count, flag or predicate returns diagnostics: " + field)
			definition.objectives[0] = original.objectives[0].duplicate(true)
	for field: String in ["op", "id"]:
		for value: Variant in invalid_values:
			definition.objectives[0].predicate[field] = value
			t.check(not QuestPredicates.valid_predicate(definition.objectives[0].predicate, db), "R04 direct predicate validation is total for malformed " + field)
			t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed predicate field returns diagnostics: " + field)
			definition.objectives[0] = original.objectives[0].duplicate(true)
	for field: String in ["crowns", "items"]:
		for value: Variant in invalid_values:
			if field == "items" and value is Dictionary:
				continue
			definition.rewards[field] = value
			t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed reward field returns diagnostics: " + field)
			definition.rewards = original.rewards.duplicate(true)
	for value: Variant in invalid_values:
		definition.rewards.items["bandage"] = value
		t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed item reward count returns diagnostics")
		definition.rewards = original.rewards.duplicate(true)
		definition.consume["cart_medicine"] = value
		t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed consumed count returns diagnostics")
		definition.consume = original.consume.duplicate(true)
		definition.completion_effects = [value]
		t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed effect row returns diagnostics")
		definition.completion_effects = []
	for field: String in ["op", "id", "value"]:
		for value: Variant in invalid_values:
			if field == "value" and value is bool:
				continue
			var effect := {"op": "flag", "id": "shelter_lights", "value": true}
			effect[field] = value
			definition.completion_effects = [effect]
			t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed effect field returns diagnostics: " + field)
			definition.completion_effects = []
	for value: Variant in invalid_values:
		var predicate := {"op": "sources", "ids": value}
		t.check(not QuestPredicates.valid_predicate(predicate, db), "R04 direct source predicate rejects malformed list")
		predicate.ids = [value]
		t.check(not QuestPredicates.valid_predicate(predicate, db), "R04 direct source predicate rejects malformed source")
	for prerequisites: Array in [[], [MAIN[2]], [MAIN[3]], [MAIN[0]], [MAIN[1], MAIN[0]], [null], [[]], [{}]]:
		definition.prerequisites = prerequisites
		t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 canonical main prerequisites reject missing, skipped and cyclic edges")
	definition.prerequisites = original.prerequisites.duplicate(true)
	var side: Dictionary = db.quests[StringName(SIDES[0])].data
	side.prerequisites = [MAIN[0]]
	t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 side quests cannot acquire a main-story dependency")
	side.prerequisites = []
	var world: Dictionary = db.map
	for unavailable: Dictionary in [{}, {"scenes": []}, {"scenes": {}, "spawns": [], "exterior": null}, {"scenes": {}, "spawns": [], "exterior": {"portals": null}}]:
		db.map = unavailable
		t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 unavailable map returns quest validation diagnostics")
		t.check(not QuestPredicates.valid_predicate({"op": "defeated", "id": "captain_hall_captain_rusk_01"}, db), "R04 defeated predicate handles unavailable spawn registry")
	db.map = world.duplicate(true)
	for value: Variant in invalid_values:
		db.map.exterior.portals = [value]
		t.check(not QuestPredicates.validate_definitions(db).is_empty(), "R04 malformed portal returns validation diagnostics")
	db.map = world
	t.check(QuestPredicates.validate_definitions(db).is_empty(), "R04 canonical content survives all malformed-data mutations")
