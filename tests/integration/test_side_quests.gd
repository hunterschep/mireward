extends RefCounted
## Positioned E/Enter fixtures isolate side content; combat clears are disclosed below.

const ROWS := [
	{"id": "sq_01_a_smiths_hand", "short": "sq01", "npc": "oswin_pike", "item": "smith_hammer", "sources": ["kiln_hammer_crate"], "crowns": 12, "line": "A blade that won't apologize"},
	{"id": "sq_02_a_warm_room", "short": "sq02", "npc": "tamsin_reed", "item": "ferry_blankets", "sources": ["ferry_blanket_barrel"], "crowns": 10, "line": "investment in repeat business"},
	{"id": "sq_03_what_the_reeds_keep", "short": "sq03", "npc": "hobb_fenwick", "item": "hobb_ring", "sources": ["shrine_ring_bowl"], "crowns": 18, "line": "That's all I've got that fits"},
	{"id": "sq_04_three_small_lights", "short": "sq04", "npc": "sister_elian", "item": "votive_candle", "sources": ["monastery_candle_01", "monastery_candle_02", "monastery_candle_03"], "crowns": 15, "line": "A small answer to a large dark"},
	{"id": "sq_05_the_broken_badge", "short": "sq05", "npc": "ada_vey", "item": "ada_badge", "sources": ["watchtower_badge_locker"], "crowns": 20, "line": "lost the right to wear it"},
	{"id": "sq_06_no_clean_hands", "short": "sq06", "npc": "wren_kest", "item": "camp_medicine", "sources": ["raider_medicine_cache"], "crowns": 10},
]
var t: SceneTree
var game: MireGameRoot
var session: Node
var saves: Node
var driver: RefCounted
var previous_candle := Callable()

func run(runner: SceneTree) -> void:
	t = runner
	session = t.root.get_node("GameSession")
	saves = t.root.get_node("SaveService")
	var size: Vector2i = t.root.size
	t.root.size = Vector2i(1280, 720)
	game = load("res://scenes/game_root.tscn").instantiate()
	t.root.add_child(game)
	game.router.fade_seconds = 0
	# Reuse only T19's grounded E interaction, Enter selection and save-panel driver.
	driver = load("res://tests/integration/test_ledger_arc.gd").new()
	driver.set("t", t)
	driver.set("game", game)
	driver.set("session", session)
	driver.set("saves", saves)
	await _new_game(false)
	await _round(false, "camp", &"manual_1")
	await _gear_progress()
	await _new_game(true)
	await _round(true, "village", &"manual_2")
	await _pending_gear()
	await _gear_progress()
	await _simulated_campaign_acceptance()
	await driver._frames(2)
	game.free()
	await t.process_frame
	t.root.size = size
	t.check(not t.paused and session.recovery.player == null, "T21 complete side fixture tears down the production runtime")

func _new_game(full_pack: bool) -> void:
	t.check((await game.start_new_game(true)).ok, "T21 start a genuine fresh side-quest fixture")
	await driver._frames(3)
	# These are actual 200-damage hits and persistent deaths, not combat victory proof.
	for enemy: EnemyActor in game.router.current_world.get_node("CampaignPopulation").enemies:
		driver._defeat(enemy.entity_id)
	if full_pack:
		t.check(session.inventory.try_add(&"patched_coat", 11, &"side_fixture/full_pack").ok and session.state.inventory.size() == 16, "R25 disclosed inventory fixture fills all normal slots through the real service")
	for pair: Array in [["cart_coffer", "cart_medicine"], ["checkpoint_receipt_box", "toll_receipt"], ["watchtower_ledger_chest", "grain_ledger"]]:
		await _collect(pair[0], pair[1])
	t.check(session.state.player.crowns == 12, "T21 clearing actors and taking fixed evidence grants no automatic crowns")

func _round(early: bool, recipient: String, slot: StringName) -> void:
	if early:
		for row: Dictionary in ROWS: await _sources(row)
		for row: Dictionary in ROWS:
			t.check(session.state.quests[row.id].state == "AVAILABLE", "R33 early physical collection never silently accepts " + row.short)
	for row: Dictionary in ROWS:
		await _accept(row)
		if row.short == "sq02":
			await _rest(false)
			await _inn(false)
		if not early: await _sources(row)
		if row.short == "sq06":
			await _medicine(recipient)
		else:
			await _turn_in(row)
		if row.short == "sq02":
			await _rest(true)
			await _inn(false)
	var pending: Dictionary = session.state.pending_delivery.duplicate(true)
	t.check(session.state.player.crowns == 93 and _count("bandage") == 5, "R30 all six side rewards total85 crowns and three bandages; one paid rest costs4")
	t.check(session.state.flags.free_inn and session.state.flags.shelter_lights and session.state.flags.restored_badge, "R30 all three persistent side consequences commit")
	t.check(pending.size() == (2 if early else 0), "R25 exactly the two gear rewards remain pending only in the full-pack fixture")
	t.check(_count("arming_sword") == (0 if early else 1) and _count("kite_shield") == (0 if early else 1), "R27 each side gear reward is delivered once or retained wholly as pending")
	for row: Dictionary in ROWS:
		t.check(session.state.quests[row.id].state == "COMPLETED" and not session.state.key_items.has(row.item) and session.state.evidence.get(row.item, false), "R30 exact side item consumed with permanent evidence retained: " + row.short)
	for id: String in ["cart_medicine", "toll_receipt", "grain_ledger"]:
		t.check(session.state.key_items.get(id, 0) == 1, "R33 side handoffs retain unrelated main evidence: " + id)
	t.check(session.state.quests.mq_01_bread_and_iron.state == "AVAILABLE", "R30 side quests never commandeer the main quest")
	await driver._save_reload(slot)
	t.check(session.state.player.crowns == 93 and session.state.choices.medicine_recipient == recipient and session.state.pending_delivery.size() == pending.size(), "R38 actual save/load retains exact side rewards, selected recipient and pending gear count")
	for id: String in pending:
		t.check(session.state.pending_delivery.has(id) and session.state.pending_delivery[id].item_id == pending[id].item_id and int(session.state.pending_delivery[id].quantity) == int(pending[id].quantity), "R38 each exact pending gear identity and quantity survives JSON reload")
	var reaction: SideQuestReactions = game.router.current_world.get_node("SideQuestReactions")
	t.check(reaction.badge.visible and reaction.shelter_lights.visible and reaction.candles.size() == 3, "R30 production scene reconstructs Ada's badge and all three shelter lights")
	for row: Dictionary in ROWS:
		for source: String in row.sources:
			t.check(session.world_state.get_entity_state(StringName(source)).remaining.is_empty(), "R25 depleted fixed source remains empty after actual file reload: " + source)

func _accept(row: Dictionary) -> void:
	if row.npc == "tamsin_reed": await _inn(true)
	await driver._interact(StringName(row.npc))
	if driver._button("dialogue/accept_" + row.short) == null: await driver._ui("dialogue/offer_" + row.short)
	await driver._ui("dialogue/accept_" + row.short)
	t.check(session.state.quests[row.id].state in ["ACTIVE", "READY"], "R30 actual NPC and Enter control accept " + row.short)
	await driver._ui("dialogue/@leave")

func _sources(row: Dictionary) -> void:
	for source: String in row.sources: await _collect(source, row.item)
	t.check(session.state.key_items.get(row.item, 0) == row.sources.size(), "R33 exact carried quantity comes from canonical source identities: " + row.short)

func _collect(source: String, item: String) -> void:
	await driver._interact(StringName(source))
	t.check(game.ui.inventory.loot_id == StringName(source), "R25 physical source opens its own loot record: " + source)
	if item == "votive_candle" and previous_candle.is_valid():
		var before: Dictionary = session.snapshot()
		previous_candle.call()
		t.check(session.snapshot() == before, "R34 a prior candle callback cannot collect the newly opened distinct source")
	var stale: Callable = driver._callback("take/" + item)
	await driver._ui("take/" + item)
	t.check(session.state.evidence.get("pickup/" + source, false), "R33 E/Enter pickup records its exact authored source: " + source)
	var after: Dictionary = session.snapshot()
	if stale.is_valid():
		stale.call()
		stale.call()
	await driver._frames(2)
	t.check(session.snapshot() == after, "R34 repeated stale pickup callbacks cannot multiply " + source)
	if item == "votive_candle":
		previous_candle = stale
		t.check(not game.router.current_world.entities[StringName(source)].interaction.get_offer(&"player").allowed, "R30 an already collected candle is physically unavailable")
	await driver._back()

func _turn_in(row: Dictionary) -> void:
	if row.npc == "tamsin_reed": await _inn(true)
	await driver._interact(StringName(row.npc))
	if driver._button("dialogue/complete_" + row.short) == null: await driver._ui("dialogue/turn_in_" + row.short)
	var repeat: Callable = driver._callback("dialogue/complete_" + row.short)
	var crowns: int = session.state.player.crowns
	await driver._ui("dialogue/complete_" + row.short)
	t.check(session.state.quests[row.id].state == "COMPLETED" and session.state.player.crowns == crowns + int(row.crowns) and driver._text().contains(row.line), "R30 canonical turn-in copy and exact reward: " + row.short)
	var after: Dictionary = session.snapshot()
	if repeat.is_valid():
		repeat.call()
		repeat.call()
	await driver._frames(2)
	t.check(session.snapshot() == after, "R34 repeated completion callbacks pay once: " + row.short)
	await driver._ui("dialogue/@leave")

func _medicine(recipient: String) -> void:
	var other := "village" if recipient == "camp" else "camp"
	await _medicine_review(other)
	var opposite: Callable = driver._callback("dialogue/confirm_medicine_" + other)
	var before: Dictionary = session.snapshot()
	await driver._ui("dialogue/@leave")
	t.check(session.snapshot() == before, "R34 leaving medicine review does not deliver or consume it")
	await _medicine_review(recipient)
	before = session.snapshot()
	var stale: Callable = driver._callback("dialogue/confirm_medicine_" + recipient)
	await driver._ui("dialogue/cancel_medicine")
	if stale.is_valid(): stale.call()
	await driver._frames(2)
	t.check(session.snapshot() == before, "R34 Cancel and stale confirmation preserve the uncommitted medicine")
	await driver._ui("dialogue/review_medicine_" + recipient)
	var repeated: Callable = driver._callback("dialogue/confirm_medicine_" + recipient)
	await driver._ui("dialogue/confirm_medicine_" + recipient)
	t.check(session.state.player.crowns == int(before.player.crowns) + 10 and session.state.choices.medicine_recipient == recipient and not session.state.key_items.has("camp_medicine") and session.state.key_items.cart_medicine == 1, "R34 selected recipient alone receives the separate medicine and pays10")
	var after: Dictionary = session.snapshot()
	for callback: Callable in [stale, repeated, opposite]:
		if callback.is_valid(): callback.call()
	await driver._frames(2)
	t.check(session.snapshot() == after, "R34 duplicate and opposite-recipient callbacks cannot deliver or pay again")
	await driver._ui("dialogue/@leave")
	for npc: StringName in [&"wren_kest", &"mara_venn"]:
		await driver._interact(npc)
		t.check(driver._button("dialogue/deliver_medicine_camp") == null and driver._button("dialogue/deliver_medicine_village") == null, "R34 neither recipient offers a second delivery")
		t.check(driver._button("dialogue/ask_grain") != null if npc == &"wren_kest" else driver._button("dialogue/offer_mq01") != null or driver._button("dialogue/accept_mq01") != null, "R32 both recipients retain unrelated topics/quests")
		if driver._button("dialogue/ask_medicine_aftermath_" + recipient) != null:
			await driver._ui("dialogue/ask_medicine_aftermath_" + recipient)
		t.check(session.dialogue.view().node_id == String(npc) + "/medicine_aftermath_" + recipient and not driver._text().is_empty(), "R30 both speakers retain recipient-specific medicine aftermath")
		await driver._ui("dialogue/@leave")

func _medicine_review(recipient: String) -> void:
	await driver._interact(&"wren_kest" if recipient == "camp" else &"mara_venn")
	if driver._button("dialogue/review_medicine_" + recipient) == null: await driver._ui("dialogue/deliver_medicine_" + recipient)
	await driver._ui("dialogue/review_medicine_" + recipient)
	var copy: String = driver._text().to_lower()
	t.check(session.dialogue.view().confirmation and copy.contains("permanently consumes") and copy.contains("ten crowns") and copy.contains("other recipient") and copy.contains("cart medicine"), "R34 medicine review discloses irreversible recipient, cost and separate cart source")

func _rest(free: bool) -> void:
	await driver._interact(&"tamsin_reed")
	var suffix := "free" if free else "paid"
	await driver._ui("dialogue/ask_rest_" + suffix)
	var button: Button = driver._button("dialogue/request_rest_" + suffix)
	t.check(button != null and button.text.contains("free" if free else "4 crowns"), "R30 Tamsin displays the current inn fee")
	var crowns: int = session.state.player.crowns
	await driver._ui("dialogue/request_rest_" + suffix)
	await _settled(&"interior_inn")
	t.check(session.state.player.crowns == crowns - (0 if free else 4) and session.state.player.rest_anchor == "inn_bed", "R30 actual inn rest charges exactly the displayed fee")

func _inn(enter: bool) -> void:
	var scene_id := &"interior_inn" if enter else &"exterior"
	if game.router.loaded_scene_id == scene_id: return
	game.modes.push_mode(&"gameplay")
	var id := &"inn_door" if enter else &"inn_exit"
	var door: InteractionComponent = game.router.current_world.entities[id]
	game.player.spawn_at(Vector3(-119, 0, 134.7) if enter else Vector3(0, 0, 3.9))
	game.player.camera.look_at(door.focus_position(), Vector3.UP)
	await driver._frames(3)
	game.interaction.refresh_focus()
	t.check(game.interaction.focused == door, "T21 real ray focuses the inn transition")
	driver._set_action(&"interact", true)
	await driver._frames(1)
	driver._set_action(&"interact", false)
	await _settled(scene_id)

func _settled(scene_id: StringName) -> void:
	for frame: int in 240:
		if not session.travelling and not session.recovery.has_pending_recovery() and game.router.loaded_scene_id == scene_id: break
		await t.physics_frame
	await driver._frames(3)
	t.check(game.router.loaded_scene_id == scene_id and not session.travelling, "T21 E/Enter operation reaches terminal scene state")

func _inventory() -> void:
	game.modes.push_mode(&"gameplay")
	driver._set_action(&"inventory", true)
	await driver._frames(1)
	driver._set_action(&"inventory", false)
	await driver._frames(3)
	t.check(game.modes.mode == &"inventory", "T21 bound inventory key opens the actual inventory")

func _pending_gear() -> void:
	await _inventory()
	var pending: Dictionary = session.state.pending_delivery.duplicate(true)
	for id: String in pending:
		var before: Dictionary = session.snapshot()
		await driver._ui("claim/" + id)
		t.check(session.snapshot() == before, "R25 full-capacity claim leaves the pending reward intact")
	await driver._back()
	await driver._interact(&"oswin_pike")
	await driver._ui("dialogue/open_shop")
	for index: int in 2:
		var stack := _stack("patched_coat", true)
		await driver._ui("sell/" + stack)
	t.check(session.state.inventory.size() == 14 and session.state.player.crowns == 97, "R25 selling two spare fixture coats creates two slots and only their sale crowns")
	await driver._back()
	await _inventory()
	for id: String in pending:
		var stale: Callable = driver._callback("claim/" + id)
		await driver._ui("claim/" + id)
		var after: Dictionary = session.snapshot()
		if stale.is_valid(): stale.call()
		await driver._frames(2)
		t.check(not session.state.pending_delivery.has(id) and session.snapshot() == after, "R25 successful pending claim grants once despite stale callback")
	t.check(session.state.pending_delivery.is_empty() and _count("arming_sword") == 1 and _count("kite_shield") == 1, "R27 both side-quest gear rewards survive full capacity without duplication")
	await driver._back()

func _gear_progress() -> void:
	await _inventory()
	await driver._ui("equip/" + _stack("arming_sword"))
	await driver._ui("equip/" + _stack("kite_shield"))
	t.check(game.player.gear.current_ids.weapon == "arming_sword" and game.player.gear.current_ids.shield == "kite_shield" and game.player.combat._get_profile(&"light").damage == 24 and game.player.combat._equipped(&"shield").data.shield_cost_multiplier == 0.7, "R27 side rewards equip actual first-person models and24-damage/0.7-shield combat values")
	await driver._back()

func _simulated_campaign_acceptance() -> void:
	await driver._safe()
	var fixture: Script = load("res://tests/unit/test_quests.gd")
	t.check(fixture.ending_checkpoint(session, &"charter").ok, "T21 simulated campaign completion uses validated domain transactions, not forged quest states")
	await driver._save_reload(&"manual_3")
	for row: Dictionary in ROWS:
		await _accept(row)
		if row.npc == "tamsin_reed": await _inn(false)
	t.check(session.state.quests.mq_06_the_last_toll.state == "COMPLETED" and session.quests.journal_view().active.size() == 6, "R30 all six sides remain physically acceptable after simulated campaign completion")

func _stack(item: String, unequipped: bool = false) -> String:
	for stack: Dictionary in session.state.inventory:
		if stack.item_id == item and (not unequipped or stack.stack_id not in session.state.equipment.values()): return stack.stack_id
	return ""

func _count(item: String) -> int:
	var total: int = 0
	for stack: Dictionary in session.state.inventory:
		if stack.item_id == item: total += int(stack.quantity)
	return total
