extends RefCounted

class DamageOnTick extends Node:
	var combat: CombatComponent
	var damage: float = 10.0
	var sequence: int = 1
	func _ready() -> void:
		process_physics_priority = -15
	func _physics_process(_delta: float) -> void:
		combat.receive_hit(MireTypes.DamageRequest.new(&"healing_fixture_attacker", sequence, &"player", damage, &"light", combat.actor.global_position + Vector3.FORWARD, &"hostile"))
		queue_free()
		set_physics_process(false)

class ArenaRecovery extends RefCounted:
	var player: MirePlayer
	var session: Node
	var coordinator: EncounterCoordinator
	var reset_count: int = 0
	var pending: bool = false
	func reset() -> MireTypes.ActionResult:
		reset_count += 1
		for enemy: EnemyActor in coordinator.actors():
			if enemy.combat.dead:
				continue
			var result := enemy.reset_living_encounter()
			if not result.ok:
				return result
		return MireTypes.success()
	func travel(anchor_id: StringName, _reason: StringName, apply: bool) -> MireTypes.ActionResult:
		if anchor_id != &"village_shrine":
			return MireTypes.failure(&"fixture_route", &"This fixture only contains the village anchor.")
		if apply:
			if pending:
				session.travelling = true
				return MireTypes.success({"pending": true, "operation_id": "pending-recovery-fixture"})
			player.spawn_at(Vector3(0, 0, 9))
			session.travelling = false
		return MireTypes.success()
	func persist_defeat(entity_id: StringName) -> void:
		session.world_state.mark_defeated(entity_id)

func frames(t: SceneTree, count: int) -> void:
	for index: int in count:
		await t.physics_frame
	await t.process_frame

func count_item(session: Node, item_id: StringName) -> int:
	var count: int = 0
	for stack: Dictionary in session.state.inventory:
		if StringName(stack.item_id) == item_id:
			count += int(stack.quantity)
	return count

func spawn(arena: Node3D, player: MirePlayer, coordinator: EncounterCoordinator, archetype: StringName, at: Vector3) -> EnemyActor:
	var record: Dictionary = {}
	for source: Dictionary in arena.get_tree().root.get_node("ContentDB").map.spawns:
		if StringName(source.archetype) == archetype:
			record = source.duplicate(true)
			break
	record.position = [at.x, at.y, at.z]
	var enemy: EnemyActor = load("res://scenes/actors/enemy.tscn").instantiate()
	arena.add_child(enemy)
	enemy.configure(record, player, coordinator)
	return enemy

func run(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	var db: Node = t.root.get_node("ContentDB")
	session.new_game()
	var original_anchor: Dictionary = db.map.rest_points.village_shrine.duplicate(true)
	db.map.rest_points.village_shrine.position = [0, 0, 9]
	var arena := NavigationArena.new()
	arena.populate = false
	t.root.add_child(arena)
	await arena.navigation_ready
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	arena.add_child(player)
	player.spawn_at(Vector3(0, 0, 9))
	var coordinator := EncounterCoordinator.new()
	arena.add_child(coordinator)
	coordinator.configure(player)
	var callbacks := ArenaRecovery.new()
	callbacks.player = player
	callbacks.session = session
	callbacks.coordinator = coordinator
	var recovery: RecoveryService = session.recovery
	t.check(recovery.bind_runtime(player, coordinator.is_dangerous, callbacks.reset, callbacks.travel).ok, "R17/R22 actual autoload recovery binds real player/combat/coordinator")
	await frames(t, 3)
	var full_state: Dictionary = session.snapshot()
	t.check(not session.inventory.try_consume(&"stack_4").ok and session.state == full_state, "R17 consuming at full affected resource is refused")
	session.state.player.health = 40.0
	var nested: MireTypes.ActionResult = session.transactions.run(&"nested-consume", func(_candidate: Dictionary) -> MireTypes.ActionResult:
		return session.inventory.try_consume(&"stack_4")
	)
	t.check(not nested.ok and not recovery.is_consuming() and not session.state.transactions.has("nested-consume"), "R17 an uncommitted outer transaction cannot start a timed consumable")
	session.state.player.stamina = 30.0
	player.vitals.reset()
	var started: MireTypes.ActionResult = session.inventory.try_consume(&"stack_4")
	t.check(started.ok and recovery.is_consuming() and count_item(session, &"bandage") == 2, "R17 inventory use starts actual timed bandage without charging")
	t.check(not session.inventory.try_consume(&"stack_4").ok and not player.combat.request_attack(&"light").ok, "R17 committed consumption refuses overlapping heal and attack")
	await frames(t, 47)
	t.check(session.state.player.health == 40.0 and count_item(session, &"bandage") == 2 and session.state.player.stamina == 30.0, "R17 before 0.8 seconds bandage has no effect/cost and stamina regeneration is suspended")
	await frames(t, 2)
	t.check(session.state.player.health == 75.0 and count_item(session, &"bandage") == 1 and not recovery.is_consuming(), "R17 0.8-second completion restores 35 and charges exactly one bandage")
	await frames(t, 5)
	t.check(session.state.player.health == 75.0 and count_item(session, &"bandage") == 1, "R17 later ticks cannot repeat consumption completion")
	session.state.player.health = 92.0
	t.check(session.inventory.try_consume(&"stack_5").ok, "R17 bread starts through the inventory consume handler")
	await frames(t, 17)
	t.check(session.state.player.health == 92.0 and count_item(session, &"bread") == 1, "R17 bread cannot finish before 0.3 seconds")
	await frames(t, 2)
	t.check(session.state.player.health == 100.0 and count_item(session, &"bread") == 0, "R17 bread completion caps health at 100")
	var tonic: MireTypes.ActionResult = session.inventory.try_add(&"tonic", 1, &"healing-tonic-fixture")
	session.state.player.stamina = 20.0
	player.vitals.reset()
	t.check(session.inventory.try_consume(StringName(tonic.payload.stack_ids[0])).ok, "R17 tonic starts against stamina independently of full health")
	await frames(t, 29)
	t.check(session.state.player.stamina == 20.0 and count_item(session, &"tonic") == 1, "R17 tonic remains uncharged before 0.5 seconds")
	await frames(t, 2)
	t.check(session.state.player.stamina == 70.0 and count_item(session, &"tonic") == 0, "R17 tonic restores fifty stamina and charges once")
	session.state.player.health = 60.0
	player.combat.request_attack(&"light")
	t.check(not session.inventory.try_consume(&"stack_4").ok, "R17 actual windup prevents healing")
	await frames(t, 50)
	var bandages_before_damage: int = count_item(session, &"bandage")
	t.check(session.inventory.try_consume(&"stack_4").ok, "R17 bandage starts after actual attack recovery")
	await frames(t, 47)
	var damage := DamageOnTick.new()
	damage.combat = player.combat
	arena.add_child(damage)
	await frames(t, 2)
	t.check(session.state.player.health == 50.0 and count_item(session, &"bandage") == bandages_before_damage and not recovery.is_consuming(), "R17 damage at priority -15 on completion physics tick cancels before priority20 healing commit")
	await frames(t, 10)
	t.check(session.state.player.health == 50.0 and count_item(session, &"bandage") == bandages_before_damage, "R17 interrupted heal never charges later")
	var modes := GameModeController.new()
	arena.add_child(modes)
	modes.configure(player)
	await frames(t, 2)
	t.check(session.inventory.try_consume(&"stack_4").ok, "R17 pause fixture starts a real timed use")
	await frames(t, 20)
	modes.push_mode(&"pause")
	var elapsed: float = recovery.consumption_view().elapsed
	await t.create_timer(0.15, true, false, true).timeout
	t.check(recovery.consumption_view().elapsed == elapsed and session.state.player.health == 50.0 and session.action_locked, "R17 modal freezes the heal timer while autoload remains active")
	modes.pop_mode()
	await frames(t, 30)
	t.check(session.state.player.health == 85.0 and count_item(session, &"bandage") == 0, "R17 resuming completes the original heal exactly once")
	session.inventory.try_add(&"bandage", 3, &"quick-heal-fixture")
	session.state.player.health = 10.0
	await frames(t, 2)
	for press: int in 3:
		Input.action_press(&"quick_heal")
		await frames(t, 2)
		Input.action_release(&"quick_heal")
		await frames(t, 2)
	t.check(session.state.player.health == 10.0 and count_item(session, &"bandage") == 3, "R17 repeated Q presses cannot instantly consume stacked bandages")
	await frames(t, 40)
	t.check(session.state.player.health == 45.0 and count_item(session, &"bandage") == 2, "R17 repeated Q requests result in only the original timed heal")
	var bandage_stack: StringName
	for stack: Dictionary in session.state.inventory:
		if stack.item_id == "bandage":
			bandage_stack = StringName(stack.stack_id)
	var cart_source: StringName
	for id: StringName in db.containers:
		if db.containers[id].items.has("cart_medicine"):
			cart_source = id
	var early_key: MireTypes.ActionResult = session.world_state.take_loot(cart_source, &"cart_medicine", 1, &"recovery-key-fixture")
	session.inventory.try_add(&"wooden_buckler", 16 - session.state.inventory.size(), &"recovery-full-pockets")
	var pending_reward: MireTypes.ActionResult = session.transactions.run(&"recovery-pending-fixture", func(candidate: Dictionary) -> MireTypes.ActionResult:
		return session.inventory.stage_reward(candidate, &"arming_sword", 1, &"recovery-pending-reward")
	)
	t.check(early_key.ok and pending_reward.ok and not session.state.pending_delivery.is_empty(), "R22 death fixture contains real acquired evidence and pending equipment reward")
	var permanent_before: Dictionary = {}
	for section: String in ["key_items", "evidence", "quests", "choices", "pending_delivery", "world", "shop_stock"]:
		permanent_before[section] = session.state[section].duplicate(true)
	var before_death_items: Array = session.state.inventory.duplicate(true)
	session.state.player.crowns = 300
	session.inventory.try_consume(bandage_stack)
	var lethal := DamageOnTick.new()
	lethal.combat = player.combat
	lethal.damage = 500.0
	lethal.sequence = 2
	arena.add_child(lethal)
	await frames(t, 2)
	t.check(session.state.player.health == 0.0 and session.state.inventory == before_death_items and not recovery.is_consuming(), "R17/R22 actual combat death cancels healing without losing its item")
	var restored: MireTypes.ActionResult = recovery.confirm_death()
	t.check(restored.ok and session.state.player.crowns == 288 and player.global_position.distance_to(Vector3(0, 0.06, 9)) < 0.01 and not player.combat.dead and session.state.inventory == before_death_items, "R22 death fee commits once and real player respawns with inventory preserved")
	t.check(recovery.confirm_death().ok and session.state.player.crowns == 288, "R22 duplicate real death confirmation cannot repeat its fee")
	for section: String in permanent_before:
		t.check(session.state[section] == permanent_before[section], "R22 death preserves " + section)
	var living: EnemyActor = spawn(arena, player, coordinator, &"cutpurse", Vector3(0, 0, -9))
	var defeated: EnemyActor = spawn(arena, player, coordinator, &"levy_spearman", Vector3(5, 0, -9))
	defeated.died.connect(callbacks.persist_defeat)
	await frames(t, 5)
	living.combat.health = 7.0
	defeated.combat.receive_hit(MireTypes.DamageRequest.new(&"player", 100000, defeated.entity_id, 1000, &"light", player.global_position, &"player"))
	var collected: MireTypes.ActionResult = session.world_state.take_crowns(defeated.entity_id, &"corpse-before-rest")
	t.check(collected.ok and collected.payload.crowns == 6, "R22 defeated fixture corpse is actually looted before resting")
	var corpse_before: Dictionary = session.world_state.get_entity_state(defeated.entity_id)
	var inventory_before_rest: Array = session.state.inventory.duplicate(true)
	var stock_before_rest: Dictionary = session.state.shop_stock.duplicate(true)
	var rest_result: MireTypes.ActionResult = recovery.rest(&"village_shrine", &"actual-rest")
	t.check(rest_result.ok and living.combat.health == 45.0 and living.global_position.distance_to(living.spawn_position) < 0.1, "R22 rest callback resets the real living encounter to spawn/full health")
	t.check(defeated.combat.dead and defeated.state == &"DEAD" and session.world_state.get_entity_state(defeated.entity_id) == corpse_before and session.world_state.read_loot(defeated.entity_id).payload.crowns == 0, "R22 rest never resurrects defeated actors or refills their persistent corpse")
	t.check(session.state.inventory == inventory_before_rest and session.state.shop_stock == stock_before_rest, "R22 rest leaves inventory and merchant stock intact")
	living.global_position = Vector3(0, 0.04, 7)
	session.danger = false
	var unsafe_state: Dictionary = session.snapshot()
	t.check(not recovery.rest(&"village_shrine", &"actual-unsafe-rest").ok and session.state == unsafe_state, "R22 live nearby enemy LOS refuses rest despite a stale false danger flag")
	living.reset_living_encounter()
	callbacks.pending = true
	var pending_result: MireTypes.ActionResult = recovery.rest(&"village_shrine", &"pending-input-fixture")
	t.check(pending_result.ok and pending_result.payload.pending, "R22 real-player fixture enters pending recovery")
	await t.process_frame
	modes.push_mode(&"pause")
	modes.pop_mode()
	var locked_position: Vector3 = player.global_position
	Input.action_press(&"move_forward")
	await frames(t, 6)
	t.check(modes.mode == &"travel" and t.paused and not player.input_enabled and player.global_position == locked_position, "R22 R45 closing a panel cannot resume movement or combat during pending recovery")
	session.travelling = false
	recovery.finish_pending_travel(&"pending-recovery-fixture", MireTypes.failure(&"fixture_arrival", &"Arrival failed."))
	modes.push_mode(&"gameplay")
	await frames(t, 3)
	t.check(recovery.has_pending_recovery() and t.paused and modes.mode == &"travel" and player.global_position == locked_position, "R22 failed arrival remains safely paused when gameplay is requested")
	Input.action_release(&"move_forward")
	callbacks.pending = false
	t.check(recovery.retry_recovery().ok, "R22 pending movement lock can finish through the same recovery receipt")
	await t.process_frame
	await t.process_frame
	t.check(not t.paused and modes.mode == &"gameplay" and player.input_enabled, "R45 explicit successful recovery restores normal mode ownership and movement")
	recovery.unbind_runtime()
	db.map.rest_points.village_shrine = original_anchor
	Input.action_release(&"quick_heal")
	arena.queue_free()
	await t.process_frame
