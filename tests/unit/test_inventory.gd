extends RefCounted

var session: Node
var inventory: InventoryService
var world: WorldStateService

func run(t: SceneTree) -> void:
	session = t.root.get_node("GameSession")
	_reset()
	var initial: Dictionary = session.snapshot()
	var duplicate_service := InventoryService.new(session)
	t.check(duplicate_service.view().stacks.size() == 5 and session.state == initial, "R23 service construction does not repeat initial loadout")
	t.check(world.errors.is_empty(), "R25 authored container registry loads")
	_stack_capacity(t)
	_equipment(t)
	_rewards(t)
	_key_sources(t)
	_loot(t)
	_corpses(t)
	await _presentation_and_combat(t)
	_reset()

func _reset() -> void:
	session.new_game()
	inventory = InventoryService.new(session)
	world = WorldStateService.new(session)

func _stack_capacity(t: SceneTree) -> void:
	var before: Dictionary = session.snapshot()
	var invalid: Array[MireTypes.ActionResult] = [inventory.try_add(&"missing", 1, &"missing"), inventory.try_add(&"bread", 0, &"zero"), inventory.try_add(&"bread", -2, &"negative"), inventory.try_add(&"bread", 1, &"")]
	for result: MireTypes.ActionResult in invalid:
		t.check(not result.ok, "R23 invalid ID, count or source fails")
	t.check(session.state == before, "R23 invalid additions create no items or receipts")
	var preview := inventory.preview_add(&"bandage", 9)
	t.check(preview.ok and preview.payload.fits == 9 and session.state == before, "R24 capacity preview is read-only")
	var added := inventory.try_add(&"bandage", 9, &"bandage_bundle")
	t.check(added.ok and session.state.inventory[3].quantity == 10, "R24 existing consumable stack fills first")
	t.check(session.state.inventory[5].quantity == 1 and session.state.inventory.size() == 6, "R24 excess creates a new stack")
	var replay := inventory.try_add(&"bandage", 9, &"bandage_bundle")
	t.check(replay.ok and replay.payload.replayed and _count("bandage") == 11, "R25 repeated source grants once")
	added = inventory.try_add(&"arming_sword", 2, &"two_swords")
	t.check(added.ok and added.payload.stack_ids.size() == 2, "R24 two equipment items occupy two slots")
	for stack: Dictionary in session.state.inventory:
		var definition: MireTypes.ItemDef = session.get_node("/root/ContentDB").get_item(StringName(stack.item_id))
		t.check(stack.quantity <= definition.max_stack, "R24 every stack respects its limit")
	_reset()
	t.check(inventory.try_add(&"arming_sword", 11, &"fill").ok and session.state.inventory.size() == 16, "R24 equipped items count toward sixteen slots")
	before = session.snapshot()
	t.check(not inventory.try_add(&"tonic", 1, &"full").ok and session.state == before, "R25 full ordinary pickup fails without a receipt")
	t.check(inventory.try_add(&"cart_medicine", 1, &"key_at_capacity").ok and session.state.inventory.size() == 16, "R24 key item bypasses full normal inventory")
	var view := inventory.view()
	view.stacks[0].quantity = 0
	view.key_items.clear()
	t.check(session.state.inventory[0].quantity == 1 and session.state.key_items.cart_medicine == 1, "R24 view model is detached from live ownership")

func _equipment(t: SceneTree) -> void:
	_reset()
	var events: Array = []
	var callback := func() -> void: events.append(session.state.equipment.duplicate())
	var bus: Node = session.get_node("/root/EventBus")
	bus.equipment_changed.connect(callback)
	var added := inventory.try_add(&"arming_sword", 1, &"upgrade")
	var sword := StringName(added.payload.stack_ids[0])
	t.check(inventory.try_equip(sword).ok and session.state.equipment.weapon == String(sword), "R27 equipment state changes after owning upgrade")
	t.check(inventory.try_equip(&"stack_1").ok and inventory.try_equip(sword).ok and events.size() == 3, "R24 deliberate A B A equipment actions do not replay old receipts")
	var before: Dictionary = session.snapshot()
	session.action_locked = true
	t.check(not inventory.try_equip(&"stack_1").ok and session.state == before, "R24 committed action blocks equipment")
	t.check(not inventory.try_unequip(&"shield").ok and session.state == before, "R24 committed action blocks unequip")
	session.action_locked = false
	session.travelling = true
	t.check(not inventory.try_equip(&"stack_1").ok and session.state == before, "R24 travel blocks equipment")
	session.travelling = false
	t.check(not inventory.try_equip(&"stack_4").ok and not inventory.try_equip(&"missing").ok, "R23 non-equipment and unowned stack cannot equip")
	t.check(not inventory.try_unequip(&"weapon").ok and inventory.try_unequip(&"shield").ok, "R24 weapon replacement invariant and optional shield unequip")
	t.check(inventory.sale_check(session.snapshot(), &"stack_1", 1).ok, "R26 old weapon can be sold after replacement")
	t.check(not inventory.sale_check(session.snapshot(), sword, 1).ok, "R26 equipped weapon cannot be sold")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(session.snapshot()))
	t.check(session.restore(saved).ok, "R37 inventory snapshot survives JSON round trip")
	inventory = InventoryService.new(session)
	t.check(inventory.try_equip(&"stack_1").ok and session.state.equipment.weapon == "stack_1", "R24 recreated service avoids persisted equip receipt collisions")
	bus.equipment_changed.disconnect(callback)
	_reset()
	var candidate: Dictionary = session.snapshot()
	candidate.equipment.weapon = ""
	t.check(inventory.sale_check(candidate, &"stack_1", 1).code == &"last_weapon", "R24 final weapon protection is independent of equipped status")
	before = session.snapshot()
	t.check(inventory.try_consume(&"stack_4").code == &"unsupported" and session.state == before, "R17 timed-use hook stays honest and does not charge an item")
	inventory.consume_handler = func(stack_id: StringName) -> MireTypes.ActionResult: return MireTypes.success({"requested_stack": String(stack_id)})
	t.check(inventory.try_consume(&"stack_4").payload.requested_stack == "stack_4", "R17 later timed consumption binds through the service hook")

func _rewards(t: SceneTree) -> void:
	_reset()
	inventory.try_add(&"arming_sword", 11, &"fill")
	var result: MireTypes.ActionResult = session.transactions.run(&"quest_fixture", func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.player.crowns = int(candidate.player.crowns) + 20
		candidate.flags.free_inn = true
		return inventory.stage_reward(candidate, &"watchblade", 1, &"mq05/watchblade").event(&"currency_changed")
	)
	t.check(result.ok and result.payload.pending == 1 and session.state.player.crowns == 32 and session.state.flags.free_inn, "R25 full reward queues gear while currency and story commit")
	var before: Dictionary = session.snapshot()
	t.check(not inventory.claim_pending(&"mq05/watchblade").ok and session.state == before, "R25 failed claim remains pending without receipt")
	t.check(_remove(&"stack_5", 1, &"free_bread_slot").ok, "R25 fixture frees one slot atomically")
	result = inventory.claim_pending(&"mq05/watchblade")
	t.check(result.ok and not session.state.pending_delivery.has("mq05/watchblade") and _count("watchblade") == 1, "R25 pending claim grants and removes queue entry atomically")
	result = inventory.claim_pending(&"mq05/watchblade")
	t.check(result.ok and result.payload.replayed and _count("watchblade") == 1, "R25 repeat pending claim cannot duplicate")
	result = session.transactions.run(&"different_reward_attempt", func(candidate: Dictionary) -> MireTypes.ActionResult:
		return inventory.stage_reward(candidate, &"watchblade", 1, &"mq05/watchblade")
	)
	t.check(result.ok and result.payload.already_rewarded and _count("watchblade") == 1, "R25 stable reward identity prevents duplicate helper delivery")
	before = session.snapshot()
	result = session.transactions.run(&"failed_quest_fixture", func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.player.crowns = 999
		return inventory.stage_reward(candidate, &"missing", 1, &"invalid_reward")
	)
	t.check(not result.ok and session.state == before, "R34 invalid reward rolls back staged currency too")
	_reset()
	inventory.try_add(&"arming_sword", 11, &"fill")
	result = session.transactions.run(&"partial_reward", func(candidate: Dictionary) -> MireTypes.ActionResult:
		return inventory.stage_reward(candidate, &"bandage", 15, &"quest/bandages")
	)
	t.check(result.ok and result.payload.added == 8 and result.payload.pending == 7 and _count("bandage") == 10, "R25 fitting reward quantity enters existing stack; only excess queues")
	t.check(session.state.pending_delivery["quest/bandages"].quantity == 7 and session.validate_snapshot(session.snapshot()).ok, "R25 partial reward queue is persistent and valid")
	_reset()
	inventory.try_add(&"cart_medicine", 1, &"initial_key")
	before = session.snapshot()
	result = session.transactions.run(&"duplicate_key_reward", func(candidate: Dictionary) -> MireTypes.ActionResult:
		return inventory.stage_reward(candidate, &"cart_medicine", 1, &"duplicate/key")
	)
	t.check(not result.ok and result.code == &"capacity" and session.state == before, "R24 authored key-count overflow cannot enter pending deliveries")

func _key_sources(t: SceneTree) -> void:
	_reset()
	var before: Dictionary = session.snapshot()
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(WorldStateService.CONTAINER_PATH))
	t.check(rows.size() == 13, "R25 all thirteen authored key pickup sources exist")
	var merged_candles: Array = rows.duplicate(true)
	for index: int in range(merged_candles.size() - 1, -1, -1):
		if merged_candles[index].id in ["monastery_candle_02", "monastery_candle_03"]:
			merged_candles.remove_at(index)
		elif merged_candles[index].id == "monastery_candle_01":
			merged_candles[index].items.votive_candle = 3
	var db: Node = session.get_node("/root/ContentDB")
	t.check(not ContentValidation.container_registry(merged_candles, db.items, db.map.spawns).is_empty(), "R30 validator rejects three candles merged into one persistent pickup")
	var merged_keys: Array = rows.duplicate(true)
	merged_keys[0].items.toll_receipt = 1
	merged_keys.remove_at(1)
	t.check(not ContentValidation.container_registry(merged_keys, db.items, db.map.spawns).is_empty(), "R04 validator rejects two quest items sharing a source flag")
	for row: Dictionary in rows:
		var read := world.read_loot(StringName(row.id))
		t.check(read.ok and session.state == before, "R25 reading authored loot never initializes saved state")
	for row: Dictionary in rows:
		var item_id: String = row.items.keys()[0]
		var taken := world.take_loot(StringName(row.id), StringName(item_id), 1, StringName("pickup/" + row.id))
		t.check(taken.ok and session.state.evidence[item_id] and session.state.evidence["pickup/" + row.id], "R33 pickup records item and unique source evidence")
	t.check(session.state.key_items.votive_candle == 3 and session.state.key_items.size() == 11 and session.state.inventory.size() == 5, "R24 three candles and eleven distinct keys remain separate")
	var result: MireTypes.ActionResult = session.transactions.run(&"hand_in_cart", func(candidate: Dictionary) -> MireTypes.ActionResult:
		return inventory.stage_remove_key(candidate, &"cart_medicine", 1)
	)
	t.check(result.ok and not session.state.key_items.has("cart_medicine") and session.state.evidence.cart_medicine and session.state.evidence["pickup/cart_coffer"], "R33 hand-in removes carried key while retaining permanent evidence")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(session.snapshot()))
	t.check(session.restore(saved).ok, "R37 key and empty-container state survives JSON reload")
	world = WorldStateService.new(session)
	t.check(world.errors.is_empty() and world.read_loot(&"cart_coffer").payload.empty, "R25 reconstructing world service does not refill claimed containers")
	before = session.snapshot()
	t.check(not world.take_loot(&"cart_coffer", &"cart_medicine", 1, &"take_after_reload").ok and session.state == before, "R25 empty source cannot be collected again with new transaction ID")
	t.check(not inventory.try_add(&"votive_candle", 1, &"fourth_candle").ok, "R24 authored candle count is capped at three")
	t.check(not inventory.sale_check(session.snapshot(), &"cart_medicine", 1).ok, "R24 key identities cannot enter normal sale path")

func _loot(t: SceneTree) -> void:
	_reset()
	var db: Node = session.get_node("/root/ContentDB")
	db.containers["fixture_crate"] = {"id": "fixture_crate", "label": "Test crate", "items": {"bandage": 15, "bread": 2}, "crowns": 3}
	t.check(world.define_loot(&"fixture_crate", {"bandage": 15, "bread": 2}, 3).ok, "R25 authored ordinary loot can be registered without random grants")
	t.check(not world.define_loot(&"fixture_crate", {"tonic": 99}).ok, "R25 definition cannot be replaced to refill loot")
	t.check(not world.define_loot(&"bad", {"missing": 1}).ok and not world.define_loot(&"fractional", {"bread": 1.5}).ok, "R25 invalid loot definitions are rejected")
	inventory.try_add(&"arming_sword", 11, &"fill")
	var taken := world.take_loot(&"fixture_crate", &"bandage", 15, &"first_partial")
	t.check(taken.ok and taken.payload.added == 8 and world.read_loot(&"fixture_crate").payload.items.bandage == 7, "R25 partial pickup preserves exactly the unfitting quantity")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(session.snapshot()))
	t.check(session.restore(saved).ok, "R37 partially collected ordinary loot survives JSON reload")
	world = WorldStateService.new(session)
	t.check(world.read_loot(&"fixture_crate").payload.items.bandage == 7, "R25 rebuilt world uses saved remainder rather than initial loot")
	var before: Dictionary = session.snapshot()
	t.check(world.take_loot(&"fixture_crate", &"bandage", 15, &"first_partial").payload.replayed and session.state == before, "R25 duplicate partial pickup request does not consume more")
	t.check(not world.take_loot(&"fixture_crate", &"bandage", 7, &"full_pickup").ok and session.state == before, "R25 full-capacity pickup leaves container and receipt ledger untouched")
	t.check(not world.take_loot(&"fixture_crate", &"bandage", 8, &"too_many").ok, "R25 stale quantity request cannot overdraw container")
	t.check(_remove(&"stack_5", 1, &"free_slot").ok, "R25 free normal slot for remaining loot")
	t.check(world.take_loot(&"fixture_crate", &"bandage", 7, &"remaining_pickup").ok and _count("bandage") == 17, "R25 a deliberate later pickup takes remaining quantity")
	t.check(world.read_loot(&"fixture_crate").payload.items == {"bread": 2}, "R25 other container items survive partial collection")
	t.check(world.take_crowns(&"fixture_crate", &"crate_gold").ok and session.state.player.crowns == 15, "R25 currency pickup is independent of full stack capacity")
	before = session.snapshot()
	t.check(world.take_crowns(&"fixture_crate", &"crate_gold").payload.replayed and not world.take_crowns(&"fixture_crate", &"different_gold").ok and session.state == before, "R25 crowns can be taken only once across request identities")
	t.check(not world.apply_transaction({"fixture_crate": {"remaining": {"bread": 99}}}, &"refill").ok, "R25 generic world changes cannot refill loot")
	t.check(world.apply_transaction({"test_door": {"opened": true}}, &"door_open").ok, "R04 story state uses generic world transaction")
	before = session.snapshot()
	t.check(not world.apply_transaction({"test_door": {"opened": false}}, &"door_reset").ok and session.state == before, "R04 durable opened state cannot regress")
	var record := world.get_entity_state(&"fixture_crate")
	record.remaining.clear()
	t.check(world.read_loot(&"fixture_crate").payload.items == {"bread": 2}, "R25 world views cannot mutate live remaining loot")
	session.new_game()
	db.containers.erase("fixture_crate")

func _corpses(t: SceneTree) -> void:
	_reset()
	var id: StringName = &"south_cart_cutpurse_01"
	var before: Dictionary = session.snapshot()
	t.check(not world.read_loot(id).ok and not world.take_crowns(id, &"living_gold").ok and session.state == before, "R25 living authored enemies expose no collectible loot")
	var defeated: Array = []
	var callback := func(entity_id: StringName) -> void: defeated.append([String(entity_id), world.get_entity_state(entity_id).defeated])
	var bus: Node = session.get_node("/root/EventBus")
	bus.entity_defeated.connect(callback)
	t.check(world.mark_defeated(id).ok and session.state.player.crowns == 12, "R25 defeat persists without automatic currency payment")
	t.check(defeated == [[String(id), true]], "R04 defeat notification observes committed world state")
	t.check(world.mark_defeated(id).payload.replayed and defeated.size() == 1, "R25 repeated defeat emits once")
	t.check(world.read_loot(id).payload.crowns == 4, "R25 corpse crowns derive exactly from EnemyDef")
	t.check(world.take_crowns(id, &"corpse_gold").ok and session.state.player.crowns == 16, "R25 corpse gold granted on pickup only")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(session.snapshot()))
	t.check(session.restore(saved).ok, "R37 corpse snapshot is JSON-safe")
	world = WorldStateService.new(session)
	t.check(world.get_entity_state(id).defeated and world.read_loot(id).payload.empty, "R25 corpse stays defeated and empty after reload")
	t.check(not world.mark_defeated(&"unregistered_enemy").ok, "R25 unknown hostiles cannot create corpse rewards")
	t.check(not world.apply_transaction({String(id): {"defeated": false}}, &"resurrect").ok, "R25 generic world state cannot resurrect a defeated enemy")
	bus.entity_defeated.disconnect(callback)

func _presentation_and_combat(t: SceneTree) -> void:
	_reset()
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	player.set_physics_process(false)
	var combat: CombatComponent = player.get_node("Combat")
	combat.input_driven = false
	combat.set_physics_process(false)
	await t.process_frame
	var cases: Array[Array] = [["rusted_sword", 18], ["arming_sword", 24], ["falchion", 29], ["watchblade", 26]]
	for entry: Array in cases:
		var id: StringName = StringName(entry[0])
		var stack_id: StringName = &"stack_1"
		if id != &"rusted_sword":
			stack_id = StringName(inventory.try_add(id, 1, StringName("combat/" + String(id))).payload.stack_ids[0])
		combat.reset_combat()
		session.state.player.stamina = 100.0
		t.check(inventory.try_equip(stack_id).ok and player.gear.current_ids.weapon == String(id), "R27 committed equipment event refreshes first-person " + String(id))
		t.check(combat.request_attack(&"light").ok and combat.attack_profile.damage == entry[1], "R27 actual equipped " + String(id) + " changes combat damage")
		t.check(not inventory.try_equip(&"stack_1").ok, "R24 actual combat windup prevents equipment change")
	combat.reset_combat()
	var mail_id := StringName(inventory.try_add(&"mail_coat", 1, &"combat/mail").payload.stack_ids[0])
	t.check(inventory.try_equip(mail_id).ok and player.gear.current_ids.armor == "mail_coat", "R27 armor equipment event refreshes first-person sleeves")
	session.state.player.health = 100.0
	var damage := combat.receive_hit(MireTypes.DamageRequest.new(&"inventory_fixture", 1, &"player", 20, &"light", Vector3(0, 0, -2), &"hostile"))
	t.check(damage.health_damage == 15 and session.state.player.health == 85, "R27 actual equipped mail reduces incoming damage by25percent")
	for entry: Array in [["wooden_buckler", 16], ["kite_shield", 12]]:
		combat.reset_combat()
		session.state.player.stamina = 100.0
		var shield_id: StringName = &"stack_2"
		if entry[0] == "kite_shield":
			shield_id = StringName(inventory.try_add(&"kite_shield", 1, &"combat/kite").payload.stack_ids[0])
		t.check(inventory.try_equip(shield_id).ok and player.gear.current_ids.shield == entry[0], "R27 shield equipment event refreshes first-person gear")
		combat.set_guard(true)
		combat.advance(0.4)
		damage = combat.receive_hit(MireTypes.DamageRequest.new(&"inventory_fixture", 2 if entry[0] == "wooden_buckler" else 3, &"player", 20, &"light", Vector3(0, 0, -2), &"hostile"))
		t.check(damage.outcome == &"blocked" and damage.stamina_damage == entry[1], "R27 actual shield tier changes guard stamina cost")
	player.free()
	await t.process_frame

func _count(item_id: String) -> int:
	var total: int = 0
	for stack: Dictionary in session.state.inventory:
		if stack.item_id == item_id:
			total += int(stack.quantity)
	return total

func _remove(stack_id: StringName, quantity: int, txid: StringName) -> MireTypes.ActionResult:
	return session.transactions.run(txid, func(candidate: Dictionary) -> MireTypes.ActionResult:
		return inventory.stage_remove(candidate, stack_id, quantity)
	)
