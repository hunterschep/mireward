extends RefCounted

class ArrivalBlocker extends StaticBody3D:
	var entries: int = 0
	func _enter_tree() -> void:
		entries += 1
		collision_layer = MireTypes.WORLD if entries > 1 else 0

var _terminal: Dictionary = {}
var _discovered: Array[StringName] = []
var _fixture_player: MirePlayer

func run(t: SceneTree) -> void:
	if OS.get_environment("MIREWARD_TRAVEL_PRESENTATION") == "1":
		await _mode_and_fade(t)
		return
	if OS.get_environment("MIREWARD_WALK_INTERIORS") == "1":
		await _walk_interior_routes(t)
		return
	var session: Node = t.root.get_node("GameSession")
	var bus: Node = t.root.get_node("EventBus")
	var db: Node = t.root.get_node("ContentDB")
	session.new_game()
	var container := Node3D.new()
	t.root.add_child(container)
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	player.set_physics_process(false)
	(player.combat as CombatComponent).input_driven = false
	var router := WorldRouter.new()
	t.root.add_child(router)
	router.fade_seconds = 0
	t.check(router.configure(player, container).ok, "R06 router binds one persistent player")
	router.travel_completed.connect(func(id: StringName, result: MireTypes.ActionResult) -> void: _terminal[id] = result)
	bus.landmark_discovered.connect(_on_discovery)
	t.check(session.recovery.bind_runtime(player, router.is_dangerous, router.reset_living_encounters, router.recovery_travel).ok, "R22 recovery binds real world routes")
	var before: Dictionary = session.snapshot()
	t.check(not router.travel(&"missing", &"entry").ok and not router.travel(&"interior_inn", &"missing").ok, "R06 unknown scene and entrance fail")
	t.check(not router.travel(&"interior_undercroft", &"entry").ok, "R06 early undercroft gate rejects travel")
	t.check(before == session.snapshot() and not session.travelling, "R06 invalid routes mutate no snapshot or travel state")
	await _arrive(t, router, router.travel(&"exterior", &"start"))
	t.check(router.loaded_scene_id == &"exterior" and player.global_position.distance_to(Vector3(32, 0.06, 252)) < 0.01, "R06 opening arrival uses stable start transform")
	t.check(router.current_world.entities.size() == 6, "R06 exterior has three door and three rest adapters")
	var inventory: Array = session.state.inventory.duplicate(true)
	var player_identity: int = player.get_instance_id()
	session.transactions.run(&"test/open_undercroft", func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.flags.undercroft_open = true
		return MireTypes.success()
	)
	for suffix: String in ["inn", "crypt", "undercroft"]:
		for trip: int in 10:
			var old_world: WeakRef = weakref(router.current_world)
			await _arrive(t, router, router.travel(StringName("interior_" + suffix), &"entry"))
			t.check(old_world.get_ref() == null, "R06 old world freed on interior trip " + str(trip))
			t.check(player.get_instance_id() == player_identity and t.get_nodes_in_group("player").size() == 1, "R06 player persists without duplication")
			t.check(session.state.inventory == inventory and container.get_child_count() == 1, "R06 travel preserves inventory and one loaded world")
			t.check(router.validate_anchor(router.current_world, router.current_world.entrances[&"entry"]).ok, "R06 interior entry is grounded navigable and clear")
			if trip == 0:
				await _check_rooms(t, router)
			await _arrive(t, router, router.travel(&"exterior", StringName("from_" + suffix)))
			t.check(router.current_world.entities.size() == 6, "R06 adapters do not accumulate across round trips")
			t.check(router.validate_anchor(router.current_world, router.current_world.entrances[StringName("from_" + suffix)]).ok, "R06 exterior return clears doorway and colliders")
	# Exactly nine real discovery Areas; each emits one committed event.
	for landmark: Dictionary in db.map.landmarks:
		player.spawn_at(Vector3(landmark.position[0], landmark.position[1], landmark.position[2]))
		for frame: int in 4:
			await t.physics_frame
		player.spawn_at(Vector3(32, 0, 252))
		for frame: int in 3:
			await t.physics_frame
		player.spawn_at(Vector3(landmark.position[0], landmark.position[1], landmark.position[2]))
		for frame: int in 3:
			await t.physics_frame
	t.check(session.state.discoveries.size() == 9 and _discovered.size() == 9, "R10 nine physical discovery triggers commit once")
	var snapshot: Dictionary = session.snapshot()
	var existing := router.current_world
	var prepared: MireTypes.ActionResult = await router.prepare_restore(snapshot)
	t.check(prepared.ok and router.current_world == existing and session.snapshot() == snapshot, "R38 prepared load leaves live scene and snapshot untouched")
	if prepared.ok:
		await _arrive(t, router, router.commit_restore(StringName(prepared.payload.prepared_token)))
	t.check(session.state.discoveries.size() == 9 and _discovered.size() == 9, "R10 discoveries survive prepared restore without replaying events")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.player.scene_id = "unknown"
	before = session.snapshot()
	var failed: MireTypes.ActionResult = await router.prepare_restore(invalid)
	t.check(not failed.ok and before == session.snapshot(), "R38 invalid detached candidate leaves live state intact")
	await _recovery_cases(t, router, player, session)
	await _enemy_teardown(t, router, player, session, db)
	await _failure_and_persistence(t, router, player, session)
	bus.landmark_discovered.disconnect(_on_discovery)
	session.recovery.unbind_runtime()
	router.free()
	container.free()
	player.free()
	await t.physics_frame
	session.new_game()

func _arrive(t: SceneTree, router: WorldRouter, accepted: MireTypes.ActionResult) -> void:
	t.check(accepted.ok and accepted.payload.get("pending", false) and accepted.payload.has("operation_id"), "R06 transition accepts a unique pending operation")
	if not accepted.ok:
		printerr("TRAVEL_REJECTION " + String(accepted.message_key))
		return
	var id := StringName(accepted.payload.operation_id)
	t.check(t.root.get_node("GameSession").travelling and not router.player.input_enabled, "R06 transition holds input lock before asynchronous work")
	for frame: int in 180:
		if _terminal.has(id):
			break
		await t.physics_frame
	t.check(_terminal.has(id), "R06 travel delivers a terminal result")
	if _terminal.has(id):
		var result: MireTypes.ActionResult = _terminal[id]
		t.check(result.ok, "R06 terminal arrival succeeds: " + String(result.message_key))
		_terminal.erase(id)
	t.check(not t.root.get_node("GameSession").travelling, "R06 terminal notification follows cleared travelling flag")

func _check_rooms(t: SceneTree, router: WorldRouter) -> void:
	var interior: MireInterior = router.current_world
	t.check(interior.is_navigation_ready(), "R06 interior scene publishes navigation readiness")
	var map_rid: RID = interior.get_world_3d().navigation_map
	for room_id: StringName in interior.rooms:
		var target: Vector3 = interior.rooms[room_id]
		var path := NavigationServer3D.map_get_path(map_rid, Vector3(0, 0, 3), target, true)
		t.check(path.size() > 1 and path[-1].distance_to(target) < 0.65, "R06 traversable layout reaches " + String(room_id))
	for spawn: Dictionary in t.root.get_node("ContentDB").map.spawns:
		if spawn.scene_id == String(interior.scene_id):
			t.check(router.validate_anchor(interior, Transform3D(Basis.IDENTITY, Vector3(spawn.position[0], spawn.position[1], spawn.position[2]))).ok, "R06 authored future encounter spawn remains clear: " + String(spawn.id))

func _recovery_cases(t: SceneTree, router: WorldRouter, player: MirePlayer, session: Node) -> void:
	var original_crowns: int = session.state.player.crowns
	var permanent: Dictionary = {"inventory": session.state.inventory.duplicate(true), "world": session.state.world.duplicate(true), "quests": session.state.quests.duplicate(true)}
	for position: Vector3 in [Vector3(-245, -2, 260), Vector3(-321, -41, 0), Vector3(321, -41, 0), Vector3(0, -41, -321), Vector3(0, -41, 321)]:
		player.spawn_at(position)
		var health_before: float = session.state.player.health
		var old_count: int = _terminal.size()
		for frame: int in 200:
			await t.physics_frame
			if _terminal.size() > old_count:
				break
		t.check(not session.travelling and player.global_position.y >= 0 and float(session.state.player.health) == maxf(1, health_before - 10), "R11 physical water/bounds recovers with exactly ten HP")
		t.check(session.state.player.crowns == original_crowns and session.state.world == permanent.world and session.state.quests == permanent.quests and session.state.inventory == permanent.inventory, "R11 hazards preserve permanent progress and crowns")
		for frame: int in 35:
			await t.physics_frame
	session.state.player.health = 5.0
	router.last_safe[&"exterior"] = Transform3D(Basis.IDENTITY, Vector3(-245, -2, 260))
	await _arrive(t, router, router.recover_player(&"invalid_position"))
	t.check(session.state.player.health == 1 and router.diagnostics.size() > 0 and player.global_position.distance_to(Vector3(-110, 0.06, 149)) < 0.01, "R11 invalid local anchor falls back to village shrine with diagnostic and one HP floor")
	for death: int in 3:
		player.combat.receive_hit(MireTypes.DamageRequest.new(&"travel_fixture", death + 1, &"player", 500, &"light", player.global_position + Vector3.FORWARD, &"hostile"))
		var crowns: int = session.state.player.crowns
		var recovered: MireTypes.ActionResult = session.recovery.confirm_death()
		await _arrive(t, router, recovered)
		t.check(not session.recovery.has_pending_recovery() and session.state.player.health == 100 and session.state.player.crowns == crowns - mini(12, floori(crowns * 0.1)), "R22 repeated confirmed deaths settle one fee and one arrival each")
	await _arrive(t, router, router.travel(&"interior_inn", &"entry"))
	player.spawn_at(Vector3(-4, 0, -2))
	await t.physics_frame
	var before: int = session.state.player.crowns
	var rested: MireTypes.ActionResult = session.recovery.rest(&"inn_bed", &"test/inn_rest")
	await _arrive(t, router, rested)
	t.check(session.state.player.crowns == before - 4 and not session.recovery.has_pending_recovery(), "R22 paid inn rest waits for actual terminal arrival")
	# Snapshot scene_id is already inn at recovery commit, while the loaded world differs.
	await _arrive(t, router, router.travel(&"interior_crypt", &"entry"))
	player.combat.receive_hit(MireTypes.DamageRequest.new(&"travel_fixture", 10, &"player", 500, &"light", player.global_position + Vector3.FORWARD, &"hostile"))
	await _arrive(t, router, session.recovery.confirm_death())
	t.check(router.loaded_scene_id == &"interior_inn" and router.current_world.scene_id == &"interior_inn", "R22 death follows actual loaded scene independently of committed snapshot scene")

func _enemy_teardown(t: SceneTree, router: WorldRouter, player: MirePlayer, session: Node, db: Node) -> void:
	await _arrive(t, router, router.travel(&"interior_crypt", &"entry"))
	var coordinator := EncounterCoordinator.new()
	router.current_world.add_child(coordinator)
	coordinator.configure(player)
	var enemy := EnemyActor.new()
	router.current_world.add_child(enemy)
	var spawn: Dictionary = {}
	for row: Dictionary in db.map.spawns:
		if row.id == "crypt_hollow_keeper_01":
			spawn = row
	var configured := enemy.configure(spawn, player, coordinator)
	t.check(configured.ok and enemy.player == player, "R06 departure fixture has a real enemy reference to persistent player")
	var old_enemy: WeakRef = weakref(enemy)
	var subscriptions: int = player.combat.phase_changed.get_connections().size()
	await _arrive(t, router, router.travel(&"exterior", &"from_crypt"))
	t.check(old_enemy.get_ref() == null and player.combat.phase_changed.get_connections().size() == subscriptions - 1, "R06 old enemy and combat listener are removed on departure")
	t.check(session.state.player.health > 0, "R06 discarded enemy cannot damage the travelling player")

func _failure_and_persistence(t: SceneTree, router: WorldRouter, player: MirePlayer, session: Node) -> void:
	var old_world: Node3D = router.current_world
	var before: Dictionary = session.snapshot()
	router.world_builder = func(world: Node3D, _snapshot: Dictionary) -> MireTypes.ActionResult:
		world.get("entrances").clear()
		return MireTypes.success()
	var failed: MireTypes.ActionResult = await router.prepare_restore(before)
	t.check(not failed.ok and session.snapshot() == before and router.current_world == old_world and not session.travelling, "R38 missing destination registry leaves current scene and state intact")
	router.world_builder = func(world: Node3D, _snapshot: Dictionary) -> MireTypes.ActionResult:
		var blocker := StaticBody3D.new()
		blocker.position = Vector3(0, 1, 3)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2, 2, 2)
		shape.shape = box
		blocker.add_child(shape)
		world.add_child(blocker)
		return MireTypes.success()
	var rejected := router.travel(&"interior_inn", &"entry")
	var operation := StringName(rejected.payload.operation_id)
	for frame: int in 180:
		if _terminal.has(operation):
			break
		await t.physics_frame
	t.check(_terminal.has(operation) and not _terminal[operation].ok and session.snapshot() == before and router.current_world == old_world and player.input_enabled, "R06 obstructed destination reports terminal failure and keeps old playable world")
	_terminal.erase(operation)
	_fixture_player = player
	router.world_builder = _build_undercroft_enemies
	await _arrive(t, router, router.travel(&"interior_undercroft", &"entry"))
	var dead_id: StringName = &"undercroft_levy_spearman_01"
	var alive_id: StringName = &"undercroft_levy_spearman_02"
	var actor: EnemyActor = router.current_world.entities[dead_id]
	actor.died.connect(session.world_state.mark_defeated)
	actor.combat.receive_hit(MireTypes.DamageRequest.new(&"player", 300, dead_id, 500, &"light", player.global_position, &"player"))
	var looted: MireTypes.ActionResult = session.world_state.take_crowns(dead_id, &"test/travel_corpse")
	t.check(looted.ok, "R06 persistent actor test defeats and loots an authored retainer")
	var record: Dictionary = session.world_state.get_entity_state(dead_id)
	var living: EnemyActor = router.current_world.entities[alive_id]
	living.combat.health = 1
	var old_enemy: WeakRef = weakref(actor)
	before = session.snapshot()
	var prepared: MireTypes.ActionResult = await router.prepare_restore(before)
	t.check(prepared.ok and before == session.snapshot() and actor == router.current_world.entities[dead_id], "R38 staged enemies apply detached state without changing live world or snapshot")
	if prepared.ok:
		router.discard_prepared(StringName(prepared.payload.prepared_token))
	await _arrive(t, router, router.travel(&"exterior", &"from_undercroft"))
	await _arrive(t, router, router.travel(&"interior_undercroft", &"entry"))
	var restored_dead: EnemyActor = router.current_world.entities[dead_id]
	var restored_alive: EnemyActor = router.current_world.entities[alive_id]
	t.check(old_enemy.get_ref() == null and restored_dead.combat.dead and session.world_state.get_entity_state(dead_id) == record, "R06 defeated entity and empty corpse persist through world reconstruction")
	t.check(restored_alive.combat.health == restored_alive.combat.max_health and restored_alive.player == player and restored_alive.coordinator.actors().size() == 2, "R06 living enemy restores at full health with one player and coordinator binding")
	router.world_builder = Callable()
	_fixture_player = null

func _build_undercroft_enemies(world: Node3D, _snapshot: Dictionary) -> MireTypes.ActionResult:
	if world.get("scene_id") != &"interior_undercroft":
		return MireTypes.success()
	var coordinator := EncounterCoordinator.new()
	world.add_child(coordinator)
	# The router binds the coordinator to live player signals only on activation.
	for spawn: Dictionary in world.get_node("/root/ContentDB").map.spawns:
		if spawn.id not in ["undercroft_levy_spearman_01", "undercroft_levy_spearman_02"]:
			continue
		var enemy := EnemyActor.new()
		world.add_child(enemy)
		var result := enemy.configure(spawn, _fixture_player, coordinator)
		if not result.ok:
			return result
		world.get("entities")[StringName(spawn.id)] = enemy
	return MireTypes.success()

func _on_discovery(id: StringName) -> void:
	_discovered.append(id)

func _walk_interior_routes(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	session.new_game()
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	(player.combat as CombatComponent).input_driven = false
	var previous_scale: float = Engine.time_scale
	Engine.time_scale = 3
	for suffix: String in ["inn", "crypt", "undercroft"]:
		player.set_physics_process(false)
		var world: MireInterior = load("res://scenes/world/%s/%s.tscn" % [suffix, suffix]).instantiate()
		t.root.add_child(world)
		for frame: int in 120:
			if world.is_navigation_ready():
				break
			await t.physics_frame
		player.spawn_at(Vector3(0, 0, 3))
		player.set_physics_process(true)
		var goals: Array = world.rooms.values()
		goals.append(Vector3(0, 0, 3))
		for target: Vector3 in goals:
			var path := NavigationServer3D.map_get_path(world.get_world_3d().navigation_map, player.global_position, target, true)
			var passed: bool = path.size() > 0
			for waypoint: Vector3 in path:
				Input.action_press(&"move_forward")
				var reached: bool = false
				for frame: int in 400:
					var direction := waypoint - player.global_position
					direction.y = 0
					if direction.length() < 0.35:
						reached = true
						break
					player.rotation.y = atan2(-direction.x, -direction.z)
					await t.physics_frame
				Input.action_release(&"move_forward")
				if not reached:
					passed = false
					break
			t.check(passed and player.global_position.y > -0.1, "R06 actual player walks " + suffix + " to " + str(target))
		player.set_physics_process(false)
		world.free()
		await t.physics_frame
	Engine.time_scale = previous_scale
	player.free()
	session.new_game()

func _mode_and_fade(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	session.new_game()
	var container := Node3D.new()
	t.root.add_child(container)
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	player.set_physics_process(false)
	(player.combat as CombatComponent).input_driven = false
	var controller := GameModeController.new()
	t.root.add_child(controller)
	controller.configure(player)
	var router := WorldRouter.new()
	t.root.add_child(router)
	router.configure(player, container, controller)
	router.travel_completed.connect(func(id: StringName, result: MireTypes.ActionResult) -> void: _terminal[id] = result)
	var accepted := router.travel(&"interior_inn", &"entry")
	t.check(accepted.ok and controller.mode == &"travel" and t.paused and not player.input_enabled, "R06 mode controller owns travel pause and input lock")
	var saw_fade: bool = false
	for frame: int in 180:
		await t.process_frame
		if router._fade.color.a > 0 and router._fade.color.a <= 1:
			saw_fade = true
			break
	t.check(saw_fade, "R06 live transition advances the fade while gameplay is paused")
	await _arrive(t, router, accepted)
	t.check(controller.mode == &"gameplay" and not t.paused and player.input_enabled and is_zero_approx(router._fade.color.a), "R06 destination navigation settles before fade clears and controller resumes gameplay")
	controller.push_mode(&"pause")
	var original: Node3D = router.current_world
	router.world_builder = func(_world: Node3D, _snapshot: Dictionary) -> MireTypes.ActionResult:
		return MireTypes.failure(&"fixture_failure", &"Destination construction rejected.")
	var failed := router.travel(&"interior_crypt", &"entry")
	var id := StringName(failed.payload.operation_id)
	for frame: int in 180:
		if _terminal.has(id):
			break
		await t.physics_frame
	t.check(_terminal.has(id) and not _terminal[id].ok and router.current_world == original and controller.mode == &"pause" and t.paused, "R06 failed arrival preserves the old scene and prior modal pause")
	for prior_modes: Array in [[&"pause", &"load", &"confirmation"], [&"dialogue", &"readable"]]:
		controller.push_mode(&"gameplay")
		for prior: StringName in prior_modes:
			controller.push_mode(prior)
		var prior_stack: Array[StringName] = controller.stack.duplicate()
		failed = router.travel(&"interior_crypt", &"entry")
		id = StringName(failed.payload.operation_id)
		for frame: int in 180:
			if _terminal.has(id):
				break
			await t.physics_frame
		t.check(_terminal.has(id) and not _terminal[id].ok and controller.stack == prior_stack and t.paused and not player.input_enabled, "R06 failed arrival restores every nested modal: " + str(prior_modes))
		controller.pop_mode()
		t.check(controller.mode == prior_stack[-2], "R45 Back after failed travel reaches the original parent panel")
		for remaining: int in prior_modes.size() - 1:
			controller.pop_mode()
		t.check(controller.mode == &"gameplay" and not t.paused and player.input_enabled, "R45 failed nested travel cannot trap Back on a travel screen")
	var npc: NpcActor = load("res://scenes/actors/npc.tscn").instantiate()
	original.add_child(npc)
	npc.position = Vector3(-3, 0, -2)
	t.check(npc.configure(session, &"tamsin_reed").ok and npc.interaction.enabled, "R06 late-arrival rollback fixture has a real live NPC")
	var activations: Array[bool] = []
	router.world_activated.connect(func(world: Node3D) -> void:
		if world == original:
			activations.append(router.current_world == original and router.loaded_scene_id == original.scene_id and router.validate_anchor(original, original.entrances[&"entry"]).ok)
			npc.activate()
	)
	var listener_count: int = t.root.get_node("EventBus").quest_updated.get_connections().size()
	var prior_snapshot: Dictionary = session.snapshot()
	router.world_builder = func(world: Node3D, _snapshot: Dictionary) -> MireTypes.ActionResult:
		var blocker := ArrivalBlocker.new()
		blocker.position = Vector3(0, 1, 3)
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3, 2, 3)
		collision.shape = box
		blocker.add_child(collision)
		world.add_child(blocker)
		return MireTypes.success()
	failed = router.travel(&"interior_crypt", &"entry")
	id = StringName(failed.payload.operation_id)
	for frame: int in 180:
		if _terminal.has(id):
			break
		await t.physics_frame
	t.check(_terminal.has(id) and not _terminal[id].ok and router.current_world == original and session.snapshot() == prior_snapshot, "R38 late arrival failure rolls back world and snapshot after detaching the old scene")
	t.check(activations == [true] and npc.interaction.enabled and npc.get_parent() == original, "R06 restored world emits one activation only after identity and navigation are restored")
	t.check(t.root.get_node("EventBus").quest_updated.get_connections().size() == listener_count and npc.interaction.get_offer(&"player").allowed, "R06 late rollback restores NPC listeners and usable conversation")
	router.world_builder = Callable()
	router.free()
	controller.free()
	container.free()
	player.free()
	session.new_game()
