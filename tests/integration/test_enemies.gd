extends RefCounted

var _sequence: int = 50000

func frames(t: SceneTree, count: int = 2) -> void:
	for _index: int in count:
		await t.physics_frame
	await t.process_frame

func spawn_record(archetype: StringName, at: Vector3, toward: Vector3, index: int = 0) -> Dictionary:
	var matches: Array[Dictionary] = []
	for row: Dictionary in (Engine.get_main_loop() as SceneTree).root.get_node("ContentDB").map.spawns:
		if row.archetype == String(archetype):
			matches.append(row)
	var record: Dictionary = matches[index].duplicate(true)
	record.position = [at.x, at.y, at.z]
	var direction: Vector3 = toward - at
	record.yaw = atan2(-direction.x, -direction.z)
	return record

func enemy(t: SceneTree, arena: Node3D, player: MirePlayer, coordinator: EncounterCoordinator, archetype: StringName, at: Vector3, index: int = 0) -> EnemyActor:
	var actor: EnemyActor = load("res://scenes/actors/enemy.tscn").instantiate()
	arena.add_child(actor)
	var result: MireTypes.ActionResult = actor.configure(spawn_record(archetype, at, player.global_position, index), player, coordinator)
	t.check(result.ok, "R18 configures canonical " + String(archetype) + " actor")
	return actor

func hit(actor: EnemyActor, player: MirePlayer, damage: float) -> MireTypes.DamageResult:
	_sequence += 1
	return actor.combat.receive_hit(MireTypes.DamageRequest.new(&"player", _sequence, actor.entity_id, damage, &"light", player.global_position, &"player"))

func box(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func clear_enemies(t: SceneTree, coordinator: EncounterCoordinator) -> void:
	for actor: EnemyActor in coordinator.actors():
		actor.queue_free()
	await frames(t)
	coordinator.refresh_budget()

func run(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	session.new_game()
	var arena: Node3D = load("res://scripts/ai/navigation_arena.gd").new()
	arena.populate = false
	t.root.add_child(arena)
	await arena.navigation_ready
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	arena.add_child(player)
	player.set_input_enabled(false)
	player.combat.faction = &"neutral"
	player.global_position = Vector3(0, 0, 1.4)
	var coordinator := EncounterCoordinator.new()
	arena.add_child(coordinator)
	coordinator.configure(player)
	await frames(t, 4)
	await check_perception(t, arena, player, coordinator)
	await clear_enemies(t, coordinator)
	await check_navigation(t, arena, player, coordinator)
	await clear_enemies(t, coordinator)
	await check_crowd_and_guard(t, arena, player, coordinator)
	await clear_enemies(t, coordinator)
	await check_return_and_stuck(t, arena, player, coordinator)
	await clear_enemies(t, coordinator)
	await check_budget_and_lifecycle(t, arena, player, coordinator)
	arena.queue_free()
	await t.process_frame

func check_perception(t: SceneTree, arena: Node3D, player: MirePlayer, coordinator: EncounterCoordinator) -> void:
	var actor: EnemyActor = enemy(t, arena, player, coordinator, &"cutpurse", Vector3(0, 0, -1.4))
	coordinator.refresh_budget()
	actor.set_physics_process(false)
	actor.combat.set_physics_process(false)
	await frames(t)
	t.check(not actor.can_see_player() and not actor.can_hear(player.global_position), "R19 a wall blocks both close proximity detection and combat noise")
	player.global_position = Vector3(2.7, 0, -1.4)
	t.check(actor.can_see_player(), "R19 full-circle proximity within three meters ignores the sight cone")
	player.global_position = Vector3(0, 0, -8)
	t.check(not actor.can_see_player(), "R19 targets beyond close proximity must enter the frontal sight cone")
	actor.rotation.y = 0
	t.check(actor.can_see_player(), "R19 an unobstructed target in the 120-degree cone is visible")
	player.global_position = Vector3(0, 0, -18)
	t.check(not actor.can_see_player(), "R19 sight does not extend beyond fourteen meters")
	hit(actor, player, 1)
	t.check(actor.state == &"ALERT", "R19 actual received damage alerts its recipient outside sight range")
	actor.apply_persistent_state({"faction": "neutral"})
	var health: float = actor.combat.health
	t.check(hit(actor, player, 20).outcome == &"ignored" and actor.combat.health == health and not actor.is_alive_hostile(), "R18 explicit neutral aftermath cannot take damage or become hostile")
	actor.apply_persistent_state({"disabled": true})
	t.check(not actor.visible and actor.collision_layer == 0 and actor.hurtbox.collision_layer == 0, "R18 disabled surviving spawns leave no active body or hurtbox")
	var copy: EnemyActor = load("res://scenes/actors/enemy.tscn").instantiate()
	arena.add_child(copy)
	t.check(not copy.configure(spawn_record(&"cutpurse", Vector3.ZERO, Vector3.FORWARD), player, coordinator).ok, "R18 duplicate persistent actor IDs are rejected")
	copy.queue_free()
	await frames(t)
	t.check(coordinator.actors().size() == 1, "R19 disposing a rejected duplicate cannot unregister the real actor")

func check_navigation(t: SceneTree, arena: Node3D, player: MirePlayer, coordinator: EncounterCoordinator) -> void:
	player.global_position = Vector3(0, 0, 7)
	var actor: EnemyActor = enemy(t, arena, player, coordinator, &"cutpurse", Vector3(0, 0, -7))
	var map: RID = actor.navigation.get_navigation_map()
	var unsynchronized: RID = NavigationServer3D.map_create()
	actor.navigation.set_navigation_map(unsynchronized)
	coordinator.refresh_budget()
	actor.alert_to_player()
	await frames(t, 5)
	t.check(not actor.navigation_ready() and actor.replan_count == 0, "R19 an unsynchronized navigation map is never queried for a path")
	actor.navigation.set_navigation_map(map)
	NavigationServer3D.free_rid(unsynchronized)
	await frames(t, 3)
	t.check(actor.navigation_ready(), "R19 navigation starts after map synchronization")
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, actor.global_position, player.global_position, true)
	t.check(path.size() >= 3, "R19 authored navigation mesh routes around the solid wall")
	var started: Vector3 = actor.global_position
	var went_around: bool = false
	var crossed_wall: bool = false
	for _index: int in 270:
		await t.physics_frame
		went_around = went_around or absf(actor.global_position.x) > 2.2
		if absf(actor.global_position.z) < 1.2 and absf(actor.global_position.x) < 2.2:
			crossed_wall = true
	t.check(went_around and not crossed_wall and actor.global_position.distance_to(player.global_position) < started.distance_to(player.global_position) - 7, "R19 real CharacterBody navigation chases around the obstacle without walking through it")
	t.check(actor.replan_count <= 24, "R19 target path assignments remain bounded to five per second")
	player.combat.faction = &"player"
	var health_before: float = t.root.get_node("GameSession").state.player.health
	await frames(t, 150)
	t.check(t.root.get_node("GameSession").state.player.health < health_before, "R18 navigated enemies damage the real player through shared melee sweeps")
	player.combat.faction = &"neutral"
	t.root.get_node("GameSession").state.player.health = 100.0

func check_crowd_and_guard(t: SceneTree, arena: Node3D, player: MirePlayer, coordinator: EncounterCoordinator) -> void:
	player.global_position = Vector3(10, 0, 7)
	var archetypes: Array[StringName] = [&"cutpurse", &"levy_spearman", &"deserter_raider", &"hollow_keeper"]
	var positions: Array[Vector3] = [Vector3(8.4, 0, 7), Vector3(11.6, 0, 7), Vector3(10, 0, 5.4), Vector3(10, 0, 8.6)]
	var actors: Array[EnemyActor] = []
	var phases: Dictionary = {}
	for index: int in archetypes.size():
		var actor: EnemyActor = enemy(t, arena, player, coordinator, archetypes[index], positions[index])
		actors.append(actor)
		actor.state_changed.connect(func(next: StringName) -> void: phases[next] = true)
		t.check(actor.combat.max_health == actor.definition.max_health and actor.model.has_node("RightArm/Elbow") and actor.authored_loot().crowns == actor.definition.data.loot_crowns, "R18 " + String(archetypes[index]) + " uses canonical combat stats, articulated art, and authored loot")
	var starts: Array[float] = []
	var listener := func(_id: StringName, time: float) -> void: starts.append(time)
	coordinator.windup_started.connect(listener)
	coordinator.refresh_budget()
	var max_reservations: int = 0
	for _index: int in 210:
		await t.physics_frame
		max_reservations = maxi(max_reservations, coordinator.reservation_count)
	var separated: bool = true
	for index: int in range(1, starts.size()):
		separated = separated and starts[index] - starts[index - 1] >= 0.249
	t.check(max_reservations <= 2 and starts.size() >= 3 and separated, "R20 four enemies share at most two attack slots with at least 0.25-second windup separation")
	t.check(phases.has(&"ALERT") and phases.has(&"CHASE") and phases.has(&"WINDUP") and phases.has(&"ACTIVE") and phases.has(&"RECOVER"), "R18 enemies traverse shared attack phases and visible AI states")
	var reserved: EnemyActor
	for actor: EnemyActor in actors:
		if actor.combat.is_committed():
			reserved = actor
			break
	if reserved != null:
		var count: int = coordinator.reservation_count
		reserved.combat.apply_stagger(0.65)
		t.check(reserved.state == &"STAGGER" and coordinator.reservation_count < count, "R20 staggering an attacker releases its reservation immediately")
	else:
		t.check(false, "R20 fixture has a committed attacker to stagger")
	var deaths: Array[StringName] = []
	actors[0].died.connect(func(id: StringName) -> void: deaths.append(id))
	hit(actors[0], player, 500)
	hit(actors[0], player, 500)
	t.check(deaths.size() == 1 and actors[0].state == &"DEAD" and actors[0].hurtbox.collision_layer == 0 and not actors[0].reset_living_encounter().ok, "R18 death emits one stable-ID loot hook and cannot reset or be damaged again")
	actors[0].apply_persistent_state({"defeated": true})
	t.check(deaths.size() == 1 and actors[0].combat.dead, "R18 restoring a defeated actor creates no new defeat or loot event")
	coordinator.windup_started.disconnect(listener)
	var raider: EnemyActor = actors[2]
	for actor: EnemyActor in actors:
		if actor != raider:
			actor.queue_free()
	await frames(t)
	raider.reset_living_encounter()
	coordinator.refresh_budget()
	var began: int = -1
	var ended: int = -1
	for index: int in 430:
		await t.physics_frame
		if raider.combat.guard_held and began < 0:
			began = index
		if began >= 0 and not raider.combat.guard_held:
			ended = index
			break
	t.check(began >= 230 and ended > began and absf(float(ended - began) / 60.0 - 0.8) < 0.06, "R18 raider starts guarding after the fourth combat second and holds approximately 0.8 seconds")
	t.check(raider.combat.get_stamina() <= 40 and raider.combat.get_stamina() > 0, "R18 enemy guard resource stays owned and capped by the shared combat component")

func check_return_and_stuck(t: SceneTree, arena: Node3D, player: MirePlayer, coordinator: EncounterCoordinator) -> void:
	player.global_position = Vector3(12, 0, -2)
	var actor: EnemyActor = enemy(t, arena, player, coordinator, &"hollow_keeper", Vector3(12, 0, -8))
	var map: RID = actor.navigation.get_navigation_map()
	var empty_map: RID = NavigationServer3D.map_create()
	actor.navigation.set_navigation_map(empty_map)
	coordinator.refresh_budget()
	hit(actor, player, 15)
	var damaged: float = actor.combat.health
	player.global_position = Vector3(12, 0, 15)
	await frames(t, 200)
	t.check(actor.is_engaged(), "R19 losing sight does not disengage before the four-second interval")
	await frames(t, 60)
	t.check(actor.state == &"RETURN" and actor.combat.health == damaged, "R19 four seconds without sight enters return without immediately restoring health")
	await frames(t, 260)
	t.check(actor.combat.health == damaged, "R19 an enemy at spawn remains damaged until five safe seconds pass")
	await frames(t, 35)
	t.check(actor.state == &"IDLE" and actor.combat.health == actor.combat.max_health, "R19 returning to spawn and remaining safe restores a living enemy")
	actor.navigation.set_navigation_map(map)
	NavigationServer3D.free_rid(empty_map)
	actor.global_position = actor.spawn_position + Vector3(31, 0, 0)
	player.global_position = actor.global_position + Vector3(0, 0, 2)
	actor.alert_to_player()
	await frames(t)
	t.check(actor.state == &"RETURN" and coordinator.reservation_count == 0, "R19 crossing the thirty-meter spawn leash disengages the attacker")
	actor.reset_living_encounter()
	player.global_position = Vector3(12, 0, 15)
	var cage := Node3D.new()
	arena.add_child(cage)
	for offset: Vector3 in [Vector3(-0.6, 0.35, 0), Vector3(0.6, 0.35, 0), Vector3(0, 0.35, -0.6), Vector3(0, 0.35, 0.6)]:
		var size := Vector3(0.2, 0.7, 1.4) if absf(offset.x) > 0 else Vector3(1.4, 0.7, 0.2)
		box(cage, Vector3(12, 0, 0) + offset, size)
	actor.global_position = Vector3(12, 0.04, 0)
	actor.alert_to_player()
	coordinator.refresh_budget()
	var before_replans: int = actor.replan_count
	await frames(t, 690)
	t.check(actor.stuck_replans in [1, 2] and actor.replan_count - before_replans <= 4 and actor.recoveries == 0 and actor.visible_to_player(), "R19 blocked episodes replan once each and never teleport while visible: stuck=%d plans=%d recoveries=%d visible=%s blocked=%.2f" % [actor.stuck_replans, actor.replan_count - before_replans, actor.recoveries, actor.visible_to_player(), actor._stuck_time])
	t.check(actor.global_position.distance_to(Vector3(12, 0, 0)) < 1.0, "R19 real physics keeps the blocked enemy inside the obstacle")
	player.rotation.y = PI
	await frames(t, 3)
	t.check(actor.recoveries == 1 and actor.global_position.distance_to(actor.spawn_position) < 0.6, "R19 a hidden enemy farther than ten meters can recover to its authored spawn")
	player.rotation.y = 0
	for wall: Node3D in cage.get_children():
		wall.scale.y = 4.0
	actor.reset_living_encounter()
	actor.global_position = Vector3(12, 0.04, 0)
	player.global_position = Vector3(12, 0, 5)
	actor.alert_to_player()
	var prior_recoveries: int = actor.recoveries
	await frames(t, 690)
	t.check(not actor.visible_to_player() and actor.recoveries == prior_recoveries and actor.global_position.distance_to(player.global_position) < 10.0, "R19 a hidden blocked enemy within ten meters never teleports")
	player.global_position = Vector3(12, 0, 15)
	await frames(t, 3)
	t.check(actor.recoveries == prior_recoveries + 1, "R19 stuck recovery waits until both visibility and distance are safe")
	cage.queue_free()
	await frames(t)
	actor.reset_living_encounter()
	var record: Dictionary = spawn_record(&"hollow_keeper", actor.spawn_position, player.global_position)
	var patrol_actor: EnemyActor = load("res://scenes/actors/enemy.tscn").instantiate()
	# Use a second known keeper identity for the authored patrol fixture.
	for row: Dictionary in t.root.get_node("ContentDB").map.spawns:
		if row.archetype == "hollow_keeper" and row.id != String(actor.entity_id):
			record.id = row.id
			break
	record.position = [-12.0, 0.0, -8.0]
	record.patrol_points = [[-14.0, 0.0, -8.0], [-10.0, 0.0, -8.0]]
	arena.add_child(patrol_actor)
	t.check(patrol_actor.configure(record, player, coordinator).ok, "R18 an authored patrol uses a separate canonical entity identity")
	coordinator.refresh_budget()
	var before: Vector3 = patrol_actor.global_position
	await frames(t, 90)
	t.check(patrol_actor.state == &"PATROL" and patrol_actor.global_position.distance_to(before) > 0.5, "R18 an unengaged patrol follows authored navigation points")

func check_budget_and_lifecycle(t: SceneTree, arena: Node3D, player: MirePlayer, coordinator: EncounterCoordinator) -> void:
	player.global_position = Vector3(0, 0, 15)
	var rows: Array = t.root.get_node("ContentDB").map.spawns
	var actors: Array[EnemyActor] = []
	for index: int in 14:
		var row: Dictionary = rows[index].duplicate(true)
		row.position = [-16.0 + index * 2.0, 0.0, -12.0]
		var actor: EnemyActor = load("res://scenes/actors/enemy.tscn").instantiate()
		arena.add_child(actor)
		var result: MireTypes.ActionResult = actor.configure(row, player, coordinator)
		t.check(result.ok, "R18 budget fixture uses canonical spawn " + String(row.id))
		actors.append(actor)
	actors.back().global_position = Vector3(100, 0, 0)
	coordinator.refresh_budget()
	var thinking: int = 0
	for actor: EnemyActor in actors:
		if actor.thinking:
			thinking += 1
	t.check(thinking == 12 and coordinator.active_count == 12 and not actors.back().thinking and not actors.back().combat.is_physics_processing(), "R19 AI budget caps thinking at twelve and sleeps hostiles beyond seventy meters")
	player.global_position = actors[0].global_position + Vector3(0, 0, 10)
	t.check(coordinator.is_dangerous(), "R19 a hostile within fifteen meters and line of sight prevents safe rest")
	player.queue_free()
	await frames(t, 3)
	t.check(coordinator.player == null and actors[0].player == null and not actors[0].thinking and coordinator.reservation_count == 0 and not coordinator.is_dangerous(), "R19 player removal clears targets, simulation, reservations, and danger without stale references")
