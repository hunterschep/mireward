class_name EnemyActor
extends CharacterBody3D

signal died(entity_id: StringName)
signal state_changed(state: StringName)

const ARCHETYPES: Array[StringName] = [&"cutpurse", &"levy_spearman", &"deserter_raider", &"hollow_keeper"]
const GRAVITY: float = 16.0
const REPLAN_INTERVAL: float = 0.2

var entity_id: StringName
var definition: MireTypes.EnemyDef
var player: MirePlayer
var coordinator: EncounterCoordinator
var combat: CombatComponent
var hurtbox: CombatHurtbox
var navigation: NavigationAgent3D
var model: Node3D
var state: StringName = &"IDLE"
var spawn_position: Vector3
var spawn_yaw: float = 0.0
var replan_count: int = 0
var stuck_replans: int = 0
var recoveries: int = 0
var thinking: bool = false
var _configured: bool = false
var _registered: bool = false
var _disabled: bool = false
var _clock: float = 0.0
var _state_elapsed: float = 0.0
var _lost_sight: float = 0.0
var _safe_at_spawn: float = 0.0
var _last_seen: Vector3
var _planned_target: Vector3 = Vector3.INF
var _next_replan: float = 0.0
var _force_replan: bool = false
var _stuck_time: float = 0.0
var _stuck_replanned: bool = false
var _desired: Vector3
var _movement_delta: float = 0.0
var _intends_to_move: bool = false
var _combat_time: float = 0.0
var _next_guard: float = 4.0
var _guard_left: float = 0.0
var _guard_due: bool = false
var _death_pose: float = 0.0
var _patrol: Array[Vector3] = []
var _patrol_index: int = 0
var _circle_sign: float = 1.0
var _map_checked: RID
var _map_iteration: int = 0
var _map_ready: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -10
	collision_layer = MireTypes.HOSTILE
	collision_mask = MireTypes.WORLD | MireTypes.PLAYER
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(45.0)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.32
	collision.position.y = 0.9
	collision.shape = capsule
	add_child(collision)
	navigation = NavigationAgent3D.new()
	navigation.path_desired_distance = 0.35
	navigation.target_desired_distance = 0.4
	navigation.path_max_distance = 2.0
	navigation.radius = 0.4
	navigation.height = 1.8
	navigation.neighbor_distance = 3.0
	navigation.max_neighbors = 6
	navigation.time_horizon_agents = 0.5
	navigation.velocity_computed.connect(_on_safe_velocity)
	add_child(navigation)
	combat = CombatComponent.new()
	add_child(combat)
	combat.set_physics_process(false)
	combat.phase_changed.connect(_on_combat_phase)
	combat.hit_received.connect(_on_hit_received)
	combat.died.connect(_on_died)
	combat.staggered.connect(_on_staggered)
	hurtbox = CombatHurtbox.new()
	hurtbox.position.y = 0.9
	hurtbox.configure(combat)
	add_child(hurtbox)
	hurtbox.collision_layer = 0
	set_physics_process(false)

func configure(spawn: Dictionary, controlled_player: MirePlayer, encounter: EncounterCoordinator) -> MireTypes.ActionResult:
	if not is_node_ready() or _configured or not SessionValidation.identifier(spawn.get("id")) or not SessionValidation.identifier(spawn.get("archetype")) or not SessionValidation.vector(spawn.get("position")) or controlled_player == null or encounter == null:
		return MireTypes.failure(&"invalid_spawn", &"The enemy spawn is incomplete or already configured.")
	if spawn.has("yaw") and (not SessionValidation.number(spawn.yaw) or not is_finite(float(spawn.yaw))):
		return MireTypes.failure(&"invalid_spawn", &"The enemy facing direction is invalid.")
	var archetype := StringName(spawn.archetype)
	if not supports_archetype(archetype):
		return MireTypes.failure(&"unsupported", &"This actor supports ordinary hostile archetypes only.")
	var canonical: bool = false
	for record: Dictionary in ContentDB.map.spawns:
		if record.id == spawn.id and record.archetype == spawn.archetype:
			canonical = true
			break
	if not canonical:
		return MireTypes.failure(&"invalid_entity", &"The enemy identity does not match the world manifest.")
	var patrol_value: Variant = spawn.get("patrol_points", [])
	if not patrol_value is Array:
		return MireTypes.failure(&"invalid_spawn", &"Patrol points must be positions.")
	for point: Variant in patrol_value:
		if not SessionValidation.vector(point):
			return MireTypes.failure(&"invalid_spawn", &"A patrol point is invalid.")
	entity_id = StringName(spawn.id)
	definition = ContentDB.get_enemy(archetype)
	player = controlled_player
	coordinator = encounter
	var registered: MireTypes.ActionResult = coordinator.register_enemy(self)
	if not registered.ok:
		return registered
	_registered = true
	spawn_position = Vector3(spawn.position[0], spawn.position[1], spawn.position[2])
	spawn_yaw = float(spawn.get("yaw", 0.0))
	global_position = spawn_position + Vector3.UP * 0.04
	rotation.y = spawn_yaw
	for point: Array in patrol_value:
		_patrol.append(Vector3(point[0], point[1], point[2]))
	_circle_sign = -1.0 if hash(entity_id) % 2 == 0 else 1.0
	model = VisualFactory.actor(archetype)
	add_child(model)
	combat.configure_enemy(self, entity_id, definition)
	navigation.max_speed = float(definition.data.chase_speed)
	hurtbox.collision_layer = MireTypes.HURTBOX
	_configured = true
	_set_state(&"PATROL" if not _patrol.is_empty() else &"IDLE")
	return MireTypes.success()

func supports_archetype(archetype: StringName) -> bool:
	return archetype in ARCHETYPES

func apply_persistent_state(record: Dictionary) -> MireTypes.ActionResult:
	if not _configured or not record.get("defeated", false) is bool or not record.get("disabled", _disabled) is bool or record.get("faction", String(combat.faction)) not in ["hostile", "neutral"]:
		return MireTypes.failure(&"invalid_state", &"The enemy world record is invalid.")
	var next_disabled: bool = record.get("disabled", _disabled)
	var next_faction: StringName = StringName(record.get("faction", String(combat.faction)))
	var changed: bool = next_disabled != _disabled or next_faction != combat.faction
	_disabled = next_disabled
	combat.faction = next_faction
	if record.get("defeated", false) and not combat.dead:
		combat.health = 0
		combat.reset_combat()
		_mark_dead(false)
	elif not combat.dead and changed:
		combat.reset_combat(false)
		_set_state(&"IDLE")
		VisualFactory.pose(model, &"idle", _clock)
	collision_layer = 0 if combat.dead or _disabled else (MireTypes.NEUTRAL if combat.faction == &"neutral" else MireTypes.HOSTILE)
	hurtbox.collision_layer = MireTypes.HURTBOX if is_alive_hostile() else 0
	visible = not _disabled
	if not is_alive_hostile():
		coordinator.release_attack(entity_id)
		set_thinking(false)
	return MireTypes.success()

func reset_living_encounter() -> MireTypes.ActionResult:
	if not _configured or combat.dead:
		return MireTypes.failure(&"defeated", &"A defeated enemy cannot reset.")
	coordinator.release_attack(entity_id)
	combat.health = combat.max_health
	combat.reset_combat()
	global_position = spawn_position + Vector3.UP * 0.04
	rotation.y = spawn_yaw
	velocity = Vector3.ZERO
	_lost_sight = 0.0
	_safe_at_spawn = 0.0
	_combat_time = 0.0
	_next_guard = 4.0
	_guard_left = 0.0
	_guard_due = false
	_stuck_time = 0.0
	_stuck_replanned = false
	_planned_target = Vector3.INF
	_set_state(&"PATROL" if not _patrol.is_empty() else &"IDLE")
	return MireTypes.success()

func authored_loot() -> Dictionary:
	return {"crowns": int(definition.data.loot_crowns), "items": []} if definition != null else {"crowns": 0, "items": []}

func is_alive_hostile() -> bool:
	return _configured and not _disabled and is_instance_valid(combat) and not combat.dead and combat.faction == &"hostile"

func is_engaged() -> bool:
	return is_alive_hostile() and state in [&"ALERT", &"CHASE", &"WINDUP", &"ACTIVE", &"RECOVER", &"STAGGER"]

func set_thinking(enabled: bool) -> void:
	if thinking == enabled:
		return
	thinking = enabled
	if not enabled and is_engaged():
		_begin_return()
	combat.set_physics_process(enabled and is_alive_hostile())
	navigation.avoidance_enabled = enabled and is_alive_hostile()
	set_physics_process(enabled or (combat.dead and _death_pose < 1.0))
	if not enabled:
		velocity = Vector3.ZERO

func detach_player() -> void:
	if _configured:
		_begin_return()
	set_thinking(false)
	player = null
	if navigation_ready():
		navigation.target_position = global_position
	_planned_target = Vector3.INF

func navigation_ready() -> bool:
	var map: RID = navigation.get_navigation_map()
	if not map.is_valid():
		return false
	var iteration: int = NavigationServer3D.map_get_iteration_id(map)
	if iteration <= 0:
		return false
	if map != _map_checked or iteration != _map_iteration:
		_map_checked = map
		_map_iteration = iteration
		var owner: RID = NavigationServer3D.map_get_closest_point_owner(map, spawn_position)
		_map_ready = owner.is_valid() and NavigationServer3D.region_get_iteration_id(owner) > 0 and NavigationServer3D.map_get_closest_point(map, spawn_position).distance_to(spawn_position) <= 1.0
	return _map_ready

func can_see_player() -> bool:
	if not _player_available():
		return false
	var toward: Vector3 = player.global_position - global_position
	var distance: float = toward.length()
	if distance > float(definition.data.sight_range):
		return false
	toward.y = 0.0
	if distance > 3.0 and toward.length_squared() > 0.0001 and (-global_basis.z).dot(toward.normalized()) < float(definition.data.sight_cos):
		return false
	return has_player_line_of_sight()

func has_player_line_of_sight() -> bool:
	return _player_available() and _line_clear(global_position + Vector3.UP * 1.45, player.global_position + Vector3.UP * 1.1)

func can_hear(origin: Vector3) -> bool:
	return is_inside_tree() and global_position.distance_to(origin) <= 8.0 and _line_clear(global_position + Vector3.UP * 1.3, origin + Vector3.UP * 1.3)

func visible_to_player() -> bool:
	if not _player_available() or not is_instance_valid(player.camera):
		return false
	var point: Vector3 = global_position + Vector3.UP * 0.9
	return player.camera.is_position_in_frustum(point) and _line_clear(player.camera.global_position, point)

func alert_to_player() -> void:
	if not is_alive_hostile() or not _player_available():
		return
	_last_seen = player.global_position
	_lost_sight = 0.0
	if state in [&"IDLE", &"PATROL", &"RETURN"]:
		_set_state(&"ALERT")

func _physics_process(delta: float) -> void:
	_clock += delta
	_state_elapsed += delta
	if combat.dead:
		_death_pose = minf(1.0, _death_pose + delta * 2.0)
		VisualFactory.pose(model, &"death", _death_pose)
		if _death_pose >= 1.0:
			set_physics_process(false)
		return
	if not is_alive_hostile() or not _player_available():
		if is_engaged():
			_begin_return()
		_stop_movement(delta)
		return
	var sees: bool = can_see_player()
	if sees:
		_last_seen = player.global_position
		_lost_sight = 0.0
	elif is_engaged():
		_lost_sight += delta
	if is_engaged() and (_lost_sight >= 4.0 or global_position.distance_to(spawn_position) > float(definition.data.leash)):
		_begin_return()
	if state in [&"IDLE", &"PATROL"] and sees:
		alert_to_player()
	if is_engaged():
		_combat_time += delta
		if definition.id == &"deserter_raider" and _combat_time >= _next_guard:
			_guard_due = true
			_next_guard += 4.0
	if combat.phase == &"STAGGER":
		_stop_movement(delta)
	elif combat.is_committed():
		if combat.phase == &"WINDUP":
			_face(player.global_position, delta, 1.8)
		_stop_movement(delta)
	else:
		match state:
			&"ALERT":
				_face(_last_seen, delta, 5.0)
				_stop_movement(delta)
				if _state_elapsed >= 0.25:
					_set_state(&"CHASE")
			&"CHASE": _chase(delta, sees)
			&"RETURN": _return_to_spawn(delta, sees)
			&"PATROL":
				if global_position.distance_to(_patrol[_patrol_index]) < 0.6:
					_patrol_index = (_patrol_index + 1) % _patrol.size()
				_navigate(_patrol[_patrol_index], float(definition.data.walk_speed), delta)
			_: _stop_movement(delta)
	_update_pose()

func _chase(delta: float, sees: bool) -> void:
	if _guard_due and _guard_left <= 0.0:
		_guard_due = false
		_guard_left = 0.8
		combat.set_guard(true)
	if _guard_left > 0.0:
		_guard_left = maxf(0.0, _guard_left - delta)
		_face(_last_seen, delta, 3.0)
		_stop_movement(delta)
		if _guard_left <= 0.0:
			combat.set_guard(false)
		return
	var distance: float = global_position.distance_to(_last_seen)
	var reach: float = float(definition.data.reach)
	if sees and distance <= reach + 0.1:
		_face(_last_seen, delta, 5.0)
		if CombatMath.in_guard_cone(-global_basis.z, _last_seen - global_position) and coordinator.reserve_attack(self):
			if not combat.request_attack(&"light").ok:
				coordinator.release_attack(entity_id)
			_stop_movement(delta)
			return
		var radial: Vector3 = global_position - _last_seen
		radial.y = 0
		if radial.length_squared() < 0.01:
			radial = Vector3.RIGHT
		var circling: Vector3 = _last_seen + radial.normalized().rotated(Vector3.UP, _circle_sign * 0.5) * (reach + 0.35)
		_navigate(circling, float(definition.data.walk_speed), delta)
	else:
		_navigate(_last_seen, float(definition.data.chase_speed), delta)

func _return_to_spawn(delta: float, sees: bool) -> void:
	if sees and _state_elapsed >= 0.5 and player.global_position.distance_to(spawn_position) <= float(definition.data.leash):
		alert_to_player()
		_stop_movement(delta)
		return
	if global_position.distance_to(spawn_position) <= 0.6:
		_stop_movement(delta)
		_safe_at_spawn += delta
		if _safe_at_spawn >= 5.0:
			combat.health = combat.max_health
			combat.reset_combat(false)
			rotation.y = spawn_yaw
			_set_state(&"PATROL" if not _patrol.is_empty() else &"IDLE")
	else:
		_safe_at_spawn = 0.0
		_navigate(spawn_position, float(definition.data.walk_speed), delta)

func _begin_return() -> void:
	if not _configured or combat.dead:
		return
	if is_instance_valid(coordinator):
		coordinator.release_attack(entity_id)
	combat.reset_combat(false)
	_guard_left = 0.0
	_guard_due = false
	_combat_time = 0.0
	_next_guard = 4.0
	_safe_at_spawn = 0.0
	_set_state(&"RETURN")

func _navigate(destination: Vector3, speed: float, delta: float) -> void:
	if not navigation_ready():
		_stop_movement(delta)
		return
	if _clock >= _next_replan and (_force_replan or not _planned_target.is_finite() or destination.distance_to(_planned_target) > 0.3):
		navigation.target_position = destination
		_planned_target = destination
		_next_replan = _clock + REPLAN_INTERVAL
		_force_replan = false
		replan_count += 1
	var direction := Vector3.ZERO
	if not navigation.is_navigation_finished():
		direction = navigation.get_next_path_position() - global_position
		direction.y = 0
		if direction.length_squared() > 0.001:
			direction = direction.normalized()
	_intends_to_move = global_position.distance_to(destination) > 0.6
	if direction.length_squared() > 0.01:
		_face(global_position + direction, delta, 5.0)
	_move(direction * speed, delta)

func _stop_movement(delta: float) -> void:
	_intends_to_move = false
	_move(Vector3.ZERO, delta)

func _move(desired: Vector3, delta: float) -> void:
	_desired = desired
	_movement_delta = delta
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	if navigation.avoidance_enabled and navigation_ready():
		navigation.velocity = desired
	else:
		_on_safe_velocity(desired)

func _on_safe_velocity(safe: Vector3) -> void:
	if not thinking or combat.dead or get_tree().paused:
		return
	var before: Vector3 = global_position
	velocity.x = safe.x
	velocity.z = safe.z
	move_and_slide()
	var moved: float = Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if _intends_to_move and moved < maxf(0.001, _desired.length() * _movement_delta * 0.15):
		_stuck_time += _movement_delta
		if _stuck_time >= 2.0 and not _stuck_replanned:
			_stuck_replanned = true
			_force_replan = true
			stuck_replans += 1
		if _stuck_time >= 6.0 and _player_available() and global_position.distance_to(player.global_position) > 10.0 and not visible_to_player():
			global_position = spawn_position + Vector3.UP * 0.04
			velocity = Vector3.ZERO
			_stuck_time = 0.0
			_stuck_replanned = false
			recoveries += 1
			_begin_return()
	elif moved > 0.001 or not _intends_to_move:
		_stuck_time = 0.0
		_stuck_replanned = false

func _face(point: Vector3, delta: float, speed: float) -> void:
	var toward: Vector3 = point - global_position
	if Vector2(toward.x, toward.z).length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y, atan2(-toward.x, -toward.z), minf(1.0, speed * delta))

func _line_clear(from: Vector3, to: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from, to, MireTypes.WORLD)
	ray.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _player_available() -> bool:
	return is_instance_valid(player) and player.is_inside_tree() and not player.is_queued_for_deletion() and GameSession.active and not GameSession.travelling and float(GameSession.state.player.health) > 0

func _on_combat_phase(phase: StringName) -> void:
	if phase == &"WINDUP":
		_set_state(&"WINDUP")
		coordinator.emit_noise(global_position, entity_id)
	elif phase == &"ACTIVE":
		_set_state(&"ACTIVE")
	elif phase == &"RECOVERY":
		_set_state(&"RECOVER")
	elif phase == &"STAGGER":
		_set_state(&"STAGGER")
	elif phase == &"IDLE" and state in [&"WINDUP", &"ACTIVE", &"RECOVER", &"STAGGER"]:
		coordinator.release_attack(entity_id)
		_set_state(&"CHASE")

func _on_hit_received(_request: MireTypes.DamageRequest, result: MireTypes.DamageResult) -> void:
	if result.outcome != &"ignored" and not combat.dead:
		alert_to_player()

func _on_staggered(_seconds: float) -> void:
	coordinator.release_attack(entity_id)
	_guard_left = 0.0

func _on_died(_id: StringName) -> void:
	_mark_dead(true)

func _mark_dead(notify: bool) -> void:
	var was_dead: bool = state == &"DEAD"
	coordinator.release_attack(entity_id)
	combat.set_physics_process(false)
	navigation.avoidance_enabled = false
	collision_layer = 0
	hurtbox.collision_layer = 0
	velocity = Vector3.ZERO
	_set_state(&"DEAD")
	_death_pose = 0.0 if notify else 1.0
	VisualFactory.pose(model, &"death", _death_pose)
	set_physics_process(notify)
	if notify and not was_dead:
		died.emit(entity_id)

func _set_state(next: StringName) -> void:
	if state == next:
		return
	state = next
	_state_elapsed = 0.0
	state_changed.emit(state)

func _update_pose() -> void:
	if combat.phase == &"STAGGER":
		VisualFactory.pose(model, &"stagger", 0.5)
	elif combat.is_committed():
		var progress: float = combat.phase_elapsed / float(combat.attack_profile[String(combat.phase).to_lower()])
		var pose: StringName = &"windup" if combat.phase == &"WINDUP" else ((&"thrust" if definition.id == &"levy_spearman" else &"attack") if combat.phase == &"ACTIVE" else &"idle")
		VisualFactory.pose(model, pose, progress)
	else:
		VisualFactory.pose(model, &"guard" if combat.guard_held else (&"walk" if Vector2(velocity.x, velocity.z).length() > 0.2 else &"idle"), _clock * 4.0)

func _exit_tree() -> void:
	if _registered and is_instance_valid(coordinator):
		coordinator.unregister_enemy(entity_id)
	player = null
