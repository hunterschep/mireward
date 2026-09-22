extends RefCounted

class RuntimeFixture extends RefCounted:
	var session: Node
	var player: MirePlayer
	var dangerous: bool = false
	var fail_preflight: bool = false
	var fail_apply: bool = false
	var fail_reset: bool = false
	var pending: bool = false
	var reset_calls: int = 0
	var apply_calls: int = 0
	var operation_id: StringName
	var anchor_id: StringName
	func danger() -> bool:
		return dangerous
	func reset() -> MireTypes.ActionResult:
		reset_calls += 1
		return MireTypes.failure(&"fixture_reset", &"Fixture reset failed.") if fail_reset else MireTypes.success()
	func travel(anchor: StringName, _reason: StringName, apply: bool) -> MireTypes.ActionResult:
		if not apply:
			return MireTypes.failure(&"fixture_preflight", &"Fixture route unavailable.") if fail_preflight else MireTypes.success()
		apply_calls += 1
		if fail_apply:
			return MireTypes.failure(&"fixture_apply", &"Fixture arrival failed.")
		anchor_id = anchor
		if pending:
			operation_id = StringName("fixture-travel-%d" % apply_calls)
			session.travelling = true
			return MireTypes.success({"pending": true, "operation_id": String(operation_id)})
		arrive()
		return MireTypes.success()
	func arrive() -> void:
		var anchor: Dictionary = session.get_node("/root/ContentDB").map.rest_points[String(anchor_id)]
		player.spawn_at(Vector3(anchor.position[0], anchor.position[1], anchor.position[2]))
		session.travelling = false

func position_at(session: Node, player: MirePlayer, anchor_id: StringName) -> void:
	var anchor: Dictionary = session.get_node("/root/ContentDB").map.rest_points[String(anchor_id)]
	session.state.player.scene_id = anchor.scene_id
	player.spawn_at(Vector3(anchor.position[0], anchor.position[1], anchor.position[2]))

func run(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	var db: Node = t.root.get_node("ContentDB")
	var economy := EconomyService.new(session)
	session.new_game()
	var original: Dictionary = session.snapshot()
	t.check(not economy.try_buy(&"oswin_pike", &"arming_sword", 1, &"buy-retry").ok and session.state == original, "R26 insufficient funds preserve money, stock, inventory and ledger")
	session.state.player.crowns = 100
	var bought := economy.try_buy(&"oswin_pike", &"arming_sword", 1, &"buy-retry")
	t.check(bought.ok and session.state.player.crowns == 68 and session.state.shop_stock.oswin_pike.arming_sword == 0, "R26 a failed uncommitted purchase can retry its same identity")
	var after_buy: Dictionary = session.snapshot()
	var repeated := economy.try_buy(&"oswin_pike", &"arming_sword", 1, &"buy-retry")
	t.check(repeated.ok and repeated.payload.replayed and session.state == after_buy, "R26 committed purchase replay returns receipt without mutation")
	t.check(not economy.try_buy(&"oswin_pike", &"arming_sword", 1, &"buy-again").ok and session.state == after_buy, "R26 Oswin equipment stock is finite")
	var sword_stack := StringName(bought.payload.stack_ids[0])
	var sold := economy.try_sell(&"oswin_pike", sword_stack, 1, &"sell-once")
	t.check(sold.ok and sold.payload.total_price == 11 and session.state.player.crowns == 79 and session.state.shop_stock.oswin_pike.arming_sword == 0, "R26 selling pays floor 35 percent and never replenishes stock")
	var after_sale: Dictionary = session.snapshot()
	t.check(economy.try_sell(&"oswin_pike", sword_stack, 1, &"sell-once").ok and session.state == after_sale, "R26 sold stack replay does not duplicate currency")
	for invalid: Array in [[&"unknown", &"bread", 1], [&"tamsin_reed", &"missing_item", 1], [&"tamsin_reed", &"bread", 0], [&"tamsin_reed", &"bread", -1], [&"tamsin_reed", &"cart_medicine", 1], [&"tamsin_reed", &"bread", 9223372036854775807]]:
		var before: Dictionary = session.snapshot()
		t.check(not economy.try_buy(invalid[0], invalid[1], invalid[2], StringName("invalid-buy-%d" % t.checks)).ok and session.state == before, "R26 malformed shop/item/quantity refuses without mutation")
	t.check(not economy.try_sell(&"oswin_pike", &"stack_1", 1, &"last-weapon").ok and session.state == after_sale, "R24 last melee weapon cannot be sold")
	t.check(not economy.try_sell(&"oswin_pike", &"stack_2", 1, &"equipped-shield").ok and session.state == after_sale, "R24 equipped shield cannot be sold")
	t.check(not economy.buy_price(&"missing").ok and not economy.sell_price(&"cart_medicine").ok and not economy.view(&"missing").ok, "R26 unknown/protected price and shop queries report failure")
	for id: StringName in db.items:
		var definition: MireTypes.ItemDef = db.items[id]
		if definition.category in InventoryService.KEYS:
			continue
		for ending: StringName in [&"none", &"charter", &"warden", &"free_road"]:
			var price := economy.buy_price(id, ending)
			var resale := economy.sell_price(id)
			t.check(price.ok and resale.ok and int(price.payload.unit_price) >= int(resale.payload.unit_price) and int(resale.payload.unit_price) >= 0, "R26 no arbitrage for %s under %s" % [id, ending])
	for ending_case: Array in [["charter", 28], ["warden", 31], ["free_road", 32], ["none", 32]]:
		session.new_game()
		session.state.player.crowns = 100
		session.state.choices.ending = ending_case[0]
		var quote := economy.view(&"oswin_pike")
		var advertised: int = -1
		for row: Dictionary in quote.payload.items:
			if row.item_id == "arming_sword":
				advertised = int(row.unit_price)
		var paid := economy.try_buy(&"oswin_pike", &"arming_sword", 1, &"ending-buy")
		t.check(advertised == ending_case[1] and paid.payload.total_price == advertised and session.state.player.crowns == 100 - advertised, "R26 displayed and charged price agree for " + ending_case[0])
	session.new_game()
	session.state.player.crowns = 1000
	session.inventory.try_add(&"wooden_buckler", 11, &"fill-pockets")
	var full: Dictionary = session.snapshot()
	t.check(not economy.try_buy(&"oswin_pike", &"arming_sword", 1, &"full-buy").ok and session.state == full, "R26 full inventory changes neither stock nor crowns")
	var stacked := economy.try_buy(&"tamsin_reed", &"bandage", 8, &"stack-buy")
	t.check(stacked.ok and session.inventory.find_stack(&"stack_4").quantity == 10 and session.state.inventory.size() == 16 and session.state.shop_stock.tamsin_reed.bandage == -1, "R26 unlimited consumables still fit only available stack capacity")
	var full_stack: Dictionary = session.snapshot()
	t.check(not economy.try_buy(&"tamsin_reed", &"bandage", 1, &"stack-overflow").ok and session.state == full_stack, "R26 full consumable stack rejects excess purchase atomically")
	economy.try_sell(&"tamsin_reed", &"stack_4", 1, &"free-stack-space")
	t.check(economy.try_buy(&"tamsin_reed", &"bandage", 1, &"stack-overflow").ok and session.state.shop_stock.tamsin_reed.bandage == -1, "R26 Tamsin remains unlimited after repeated purchase and failed retry")
	var detached: MireTypes.ActionResult = economy.view(&"oswin_pike")
	detached.payload.items[0].stock = 500
	t.check(session.state.shop_stock.oswin_pike.arming_sword == 1, "R26 shop view cannot mutate live stock")
	var json_state: Dictionary = JSON.parse_string(JSON.stringify(session.snapshot()))
	t.check(session.restore(json_state).ok and economy.view(&"tamsin_reed").ok, "R26 stock and shop reads survive JSON snapshot reload")

	session.new_game()
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	var recovery := RecoveryService.new(session)
	var fixture := RuntimeFixture.new()
	fixture.player = player
	fixture.session = session
	t.check(recovery.bind_runtime(player, fixture.danger, fixture.reset, fixture.travel).ok, "R22 runtime binding validates all required recovery callbacks")
	var autosaves: Array[StringName] = []
	recovery.autosave_requested.connect(func(reason: StringName) -> void: autosaves.append(reason))
	position_at(session, player, &"inn_bed")
	session.state.player.health = 40.0
	session.state.player.stamina = 20.0
	fixture.dangerous = true
	var unsafe: Dictionary = session.snapshot()
	t.check(not recovery.rest(&"inn_bed", &"inn-rest").ok and session.state == unsafe and fixture.reset_calls == 0, "R22 unsafe inn rest refuses without charging or resetting")
	fixture.dangerous = false
	session.danger = true
	var rested := recovery.rest(&"inn_bed", &"inn-rest")
	t.check(rested.ok and rested.payload.complete and session.state.player.crowns == 8 and session.state.player.health == 100.0 and session.state.player.stamina == 100.0 and session.state.player.rest_anchor == "inn_bed", "R22 safe inn rest uses live danger and atomically charges four/refills resources")
	t.check(fixture.reset_calls == 1 and fixture.apply_calls == 1 and autosaves.size() == 1, "R22 rest resets and travels once then requests autosave")
	var rested_state: Dictionary = session.snapshot()
	t.check(recovery.rest(&"inn_bed", &"inn-rest").ok and session.state == rested_state and fixture.reset_calls == 1 and fixture.apply_calls == 1, "R22 repeated rest identity cannot charge/reset twice")
	session.state.flags.free_inn = true
	session.state.player.crowns = 0
	t.check(recovery.rest(&"inn_bed", &"free-inn").ok and session.state.player.crowns == 0, "R22 SQ02 inn flag makes subsequent rest free")
	position_at(session, player, &"village_shrine")
	t.check(recovery.rest(&"village_shrine", &"free-outdoors").ok, "R27 zero-crown character can rest at an outdoor shrine")
	t.check(not recovery.rest(&"reed_shrine", &"remote-rest").ok and not recovery.rest(&"missing", &"bad-anchor").ok, "R22 remote and unknown rest anchors are refused")
	fixture.fail_preflight = true
	var preflight: Dictionary = session.snapshot()
	t.check(not recovery.rest(&"village_shrine", &"preflight-retry").ok and session.state == preflight, "R22 failed travel preflight leaves resources and receipt intact")
	fixture.fail_preflight = false
	t.check(recovery.rest(&"village_shrine", &"preflight-retry").ok, "R22 failed preflight can retry the same rest identity")
	for penalty: Array in [[0, 0], [9, 0], [10, 1], [119, 11], [120, 12], [1000, 12]]:
		recovery.reset_runtime()
		session.new_game()
		session.state.player.crowns = penalty[0]
		session.state.player.health = 0.0
		var before_reset: int = fixture.reset_calls
		var recovered := recovery.confirm_death()
		t.check(recovered.ok and recovered.payload.charged == penalty[1] and session.state.player.crowns == penalty[0] - penalty[1] and session.state.player.health == 100.0, "R22 exact once-only death penalty for %d crowns" % penalty[0])
		var after_death: Dictionary = session.snapshot()
		t.check(recovery.confirm_death().ok and session.state == after_death and fixture.reset_calls == before_reset + 1, "R22 duplicate death confirmation cannot charge or reset twice")
	recovery.reset_runtime()
	session.new_game()
	session.state.player.crowns = 100
	session.state.player.health = 0.0
	fixture.fail_apply = true
	var failed := recovery.confirm_death()
	t.check(not failed.ok and failed.payload.committed and session.state.player.crowns == 90 and session.action_locked, "R22 failed postcommit arrival reports pending after one penalty")
	var resets_after_failure: int = fixture.reset_calls
	fixture.fail_apply = false
	t.check(recovery.confirm_death().ok and session.state.player.crowns == 90 and fixture.reset_calls == resets_after_failure, "R22 arrival retry neither charges again nor repeats completed encounter reset")
	recovery.reset_runtime()
	session.new_game()
	session.state.player.crowns = 100
	session.state.player.health = 0.0
	fixture.fail_reset = true
	var applies_before_reset_failure: int = fixture.apply_calls
	var reset_failed := recovery.confirm_death()
	t.check(not reset_failed.ok and reset_failed.payload.committed and session.state.player.crowns == 90 and fixture.apply_calls == applies_before_reset_failure, "R22 encounter reset failure leaves a committed retry without starting travel")
	fixture.fail_reset = false
	t.check(recovery.retry_recovery().ok and session.state.player.crowns == 90, "R22 encounter reset retry cannot charge a second fee")
	recovery.reset_runtime()
	session.new_game()
	session.state.player.health = 0.0
	fixture.pending = true
	var saved_count: int = autosaves.size()
	var queued := recovery.confirm_death()
	t.check(queued.ok and queued.payload.pending and not queued.payload.complete and session.travelling and recovery.has_pending_recovery() and autosaves.size() == saved_count, "R22 asynchronous travel acceptance is pending and cannot autosave")
	var old_operation: StringName = fixture.operation_id
	session.travelling = false
	recovery.advance(2.0)
	t.check(autosaves.size() == saved_count and session.action_locked, "R22 clearing travelling alone does not imply successful arrival")
	t.check(not recovery.finish_pending_travel(&"stale", MireTypes.success()).ok and autosaves.size() == saved_count, "R22 stale travel completion cannot finalize recovery")
	var failed_arrival := recovery.finish_pending_travel(old_operation, MireTypes.failure(&"fixture", &"Navigation failed."))
	t.check(not failed_arrival.ok and failed_arrival.payload.committed, "R22 explicit failed arrival retains a retryable committed receipt")
	var crowns_before_retry: int = session.state.player.crowns
	recovery.retry_recovery()
	t.check(fixture.operation_id != old_operation and session.state.player.crowns == crowns_before_retry, "R22 asynchronous retry receives a new operation without a new penalty")
	t.check(not recovery.finish_pending_travel(old_operation, MireTypes.success()).ok, "R22 late success from failed operation is ignored")
	fixture.arrive()
	var arrived := recovery.finish_pending_travel(fixture.operation_id, MireTypes.success())
	t.check(arrived.ok and arrived.payload.complete and not session.action_locked and not recovery.has_pending_recovery() and autosaves.size() == saved_count + 1, "R22 explicit final arrival unlocks input and requests exactly one save")
	recovery.unbind_runtime()
	var unbound: Dictionary = session.snapshot()
	t.check(not recovery.rest(&"village_shrine", &"unbound").ok and session.state == unbound, "R22 unbound travel cannot pretend rest succeeded")
	player.queue_free()
	await t.process_frame
