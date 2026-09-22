class_name WorldRouter
extends Node
## Owns world lifetime, never the persistent player or cursor policy.

signal travel_completed(operation_id: StringName, result: MireTypes.ActionResult)
signal world_activated(world: Node3D)
signal autosave_requested(reason: StringName)
signal diagnostic_recorded(message: String)

const SCENES := {
	&"exterior": "res://scenes/world/exterior/exterior.tscn",
	&"interior_inn": "res://scenes/world/inn/inn.tscn",
	&"interior_crypt": "res://scenes/world/crypt/crypt.tscn",
	&"interior_undercroft": "res://scenes/world/undercroft/undercroft.tscn",
}
var player: MirePlayer
var world_container: Node3D
var mode_controller: GameModeController
var current_world: Node3D
var loaded_scene_id: StringName
# Optional content factory: (world, detached_snapshot) -> ActionResult, no live mutations.
var world_builder: Callable
var fade_seconds: float = 0.12
var diagnostics: PackedStringArray = []
var last_safe: Dictionary = {}
var _fade: ColorRect
var _fade_layer: CanvasLayer
var _prepared: Dictionary = {}
var _sequence: int = 0
var _operation: StringName
var _safe_elapsed: float = 0.0
var _hazard_retry_delay: float = 0.0
var _prior_stack: Array[StringName] = [&"gameplay"]
var _prior_input: bool = true
var _preparing: bool = false

func configure(controlled_player: MirePlayer, container: Node3D, controller: GameModeController = null, fade_host: Control = null) -> MireTypes.ActionResult:
	if not is_instance_valid(controlled_player) or not is_instance_valid(container) or not controlled_player.is_inside_tree() or not container.is_inside_tree():
		return MireTypes.failure(&"invalid_runtime", &"World travel needs a persistent player and world container.")
	player = controlled_player
	world_container = container
	mode_controller = controller
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not is_instance_valid(_fade):
		_fade = ColorRect.new()
		_fade.name = "TravelFade"
		_fade.color = Color(0.05, 0.07, 0.06, 0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if fade_host != null:
			fade_host.add_child(_fade)
		else:
			_fade_layer = CanvasLayer.new()
			_fade_layer.layer = 90
			add_child(_fade_layer)
			_fade_layer.add_child(_fade)
		_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return MireTypes.success()

func travel(scene_id: StringName, entrance_id: StringName) -> MireTypes.ActionResult:
	if not GameSession.active or float(GameSession.state.player.health) <= 0:
		return MireTypes.failure(&"unavailable", &"Recover before using a doorway.")
	var available := _can_begin(false)
	if not available.ok:
		return available
	var route := _route(scene_id, entrance_id, GameSession.state)
	if not route.ok:
		return route
	return _begin({"scene_id": scene_id, "entrance_id": entrance_id, "transform": route.payload.transform, "reason": &"travel", "recovery": false})

## RecoveryService preflights before charging, then requests an asynchronous arrival.
func recovery_travel(anchor_id: StringName, reason: StringName, apply: bool) -> MireTypes.ActionResult:
	if reason not in [&"rest", &"death"] or not ContentDB.map.rest_points.has(String(anchor_id)):
		return MireTypes.failure(&"unknown_anchor", &"That recovery route does not exist.")
	var anchor: Dictionary = ContentDB.map.rest_points[String(anchor_id)]
	var destination := StringName(anchor.scene_id)
	if not SCENES.has(destination) or not ResourceLoader.exists(SCENES[destination]) or not SessionValidation.vector(anchor.position):
		return MireTypes.failure(&"unknown_scene", &"The rest point's world is unavailable.")
	var at := Transform3D(Basis.IDENTITY, _vector(anchor.position))
	if _hazard_at(destination, at.origin) or _portal_overlap(destination, at.origin):
		return MireTypes.failure(&"unsafe_anchor", &"The rest point is obstructed or hazardous.")
	if loaded_scene_id == destination and is_instance_valid(current_world):
		var checked := validate_anchor(current_world, at)
		if not checked.ok:
			return checked
	if not apply:
		return MireTypes.success({"anchor_id": String(anchor_id), "scene_id": String(destination)})
	var available := _can_begin(true)
	if not available.ok:
		return available
	return _begin({"scene_id": destination, "transform": at, "reason": reason, "recovery": true})

func recover_player(reason: StringName) -> MireTypes.ActionResult:
	if not GameSession.active or float(GameSession.state.player.health) <= 0:
		return MireTypes.failure(&"unavailable", &"Use death recovery to return to the world.")
	if GameSession.recovery.has_pending_recovery():
		return MireTypes.failure(&"busy", &"Finish the pending recovery first.")
	var available := _can_begin(true)
	if not available.ok:
		return available
	if reason not in [&"deep_water", &"bounds", &"invalid_position"]:
		return MireTypes.failure(&"invalid_reason", &"That recovery reason is not supported.")
	if not is_instance_valid(current_world):
		return MireTypes.failure(&"unavailable", &"Enter the world before recovering.")
	var destination: StringName = loaded_scene_id
	var at: Transform3D = last_safe.get(destination, Transform3D(Basis.IDENTITY, _vector(ContentDB.map.scenes[String(destination)].safe_anchor)))
	var checked := validate_anchor(current_world, at)
	if not checked.ok:
		destination = &"exterior"
		at = Transform3D(Basis.IDENTITY, _vector(ContentDB.map.rest_points.village_shrine.position))
		_record_diagnostic("Invalid local safe anchor in %s (%s); using village_shrine." % [loaded_scene_id, checked.code])
	GameSession.recovery.cancel_consume(&"Hazard interrupted item use; the item was kept.")
	return _begin({"scene_id": destination, "transform": at, "reason": reason, "recovery": false, "hazard": true})

## T14 loads remain detached until both snapshot and constructed world are valid.
func prepare_restore(candidate: Dictionary) -> MireTypes.ActionResult:
	var available := _can_begin(false)
	if not available.ok or _preparing:
		return available if not available.ok else MireTypes.failure(&"busy", &"Another world is being prepared.")
	var valid: MireTypes.ActionResult = GameSession.validate_snapshot(candidate)
	if not valid.ok:
		return valid
	_preparing = true
	var detached := candidate.duplicate(true)
	var scene_id := StringName(detached.player.scene_id)
	var at := Transform3D(Basis(Vector3.UP, float(detached.player.yaw)), _vector(detached.player.position))
	var prepared: MireTypes.ActionResult = await _prepare_world(scene_id, detached)
	_preparing = false
	if not prepared.ok:
		return prepared
	var token := StringName(prepared.payload.prepared_token)
	var record: Dictionary = _prepared[token]
	var checked := validate_anchor(record.world, at)
	if not checked.ok:
		# Saves restore to a known local safe anchor, never an arbitrary combat spot.
		at = Transform3D(Basis.IDENTITY, _vector(ContentDB.map.scenes[String(scene_id)].safe_anchor))
		checked = validate_anchor(record.world, at)
	if not checked.ok:
		discard_prepared(token)
		return checked
	record["transform"] = at
	record["snapshot"] = detached
	return MireTypes.success({"prepared_token": String(token), "scene_id": String(scene_id)})

func commit_restore(prepared_token: StringName) -> MireTypes.ActionResult:
	var available := _can_begin(false)
	if not available.ok:
		return available
	if not _prepared.has(prepared_token) or not _prepared[prepared_token].has("snapshot"):
		return MireTypes.failure(&"stale_transition", &"That prepared save is no longer available.")
	var record: Dictionary = _prepared[prepared_token]
	var valid: MireTypes.ActionResult = GameSession.validate_snapshot(record.snapshot)
	if not valid.ok:
		return valid
	return _begin({"scene_id": StringName(record.snapshot.player.scene_id), "transform": record.transform, "reason": &"load", "recovery": false, "prepared_token": prepared_token})

func discard_prepared(prepared_token: StringName) -> void:
	if not _prepared.has(prepared_token):
		return
	var record: Dictionary = _prepared[prepared_token]
	if is_instance_valid(record.viewport):
		record.viewport.free()
	_prepared.erase(prepared_token)

func is_dangerous() -> bool:
	if not is_instance_valid(current_world):
		return false
	for node: Node in current_world.find_children("*", "", true, false):
		if node is EncounterCoordinator and node.is_dangerous():
			return true
	return false

func reset_living_encounters() -> MireTypes.ActionResult:
	if not is_instance_valid(current_world):
		return MireTypes.failure(&"unavailable", &"No world is loaded.")
	for node: Node in current_world.find_children("*", "", true, false):
		if node is EnemyActor and not node.combat.dead:
			var reset: MireTypes.ActionResult = node.reset_living_encounter()
			if not reset.ok:
				return reset
	# Boss/world owner also opens the arena gate, without setting defeat flags.
	if current_world.has_method("reset_live_encounters"):
		var reset: Variant = current_world.call("reset_live_encounters")
		if not reset is MireTypes.ActionResult:
			return MireTypes.failure(&"invalid_runtime", &"The encounter reset did not return a result.")
		if not reset.ok:
			return reset
	return MireTypes.success()

func validate_anchor(world: Node3D, at: Transform3D) -> MireTypes.ActionResult:
	if not is_instance_valid(world) or not world.is_inside_tree() or not at.origin.is_finite():
		return MireTypes.failure(&"unsafe_anchor", &"The safe position is missing or invalid.")
	var scene_id := StringName(world.get("scene_id"))
	if _hazard_at(scene_id, at.origin) or _portal_overlap(scene_id, at.origin):
		return MireTypes.failure(&"unsafe_anchor", &"The safe position overlaps a hazard or doorway.")
	if not _navigation_ready(world, at.origin):
		return MireTypes.failure(&"navigation_unavailable", &"The safe position is not on ready navigation.")
	var space := world.get_world_3d().direct_space_state
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(at.origin + Vector3.UP * 0.3, at.origin - Vector3.UP * 0.4, MireTypes.WORLD))
	if ground.is_empty() or ground.normal.dot(Vector3.UP) < 0.7 or absf(ground.position.y - at.origin.y) > 0.15:
		return MireTypes.failure(&"unsafe_anchor", &"The safe position has no walkable ground.")
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.8
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at.origin + Vector3.UP * 0.98)
	query.collision_mask = MireTypes.WORLD | MireTypes.HOSTILE | MireTypes.NEUTRAL
	if not space.intersect_shape(query).is_empty():
		return MireTypes.failure(&"unsafe_anchor", &"The safe position is occupied.")
	return MireTypes.success()

func _can_begin(recovery_owned: bool) -> MireTypes.ActionResult:
	if not is_instance_valid(player) or not is_instance_valid(world_container):
		return MireTypes.failure(&"unavailable", &"World travel is not connected.")
	if not _operation.is_empty() or _preparing or GameSession.travelling or GameSession.transactions.active:
		return MireTypes.failure(&"busy", &"Wait for the current journey to finish.")
	if not recovery_owned and (GameSession.action_locked or GameSession.recovery.has_pending_recovery()):
		return MireTypes.failure(&"action_locked", &"Finish the current action before travelling.")
	return MireTypes.success()

func _route(scene_id: StringName, entrance_id: StringName, candidate: Dictionary) -> MireTypes.ActionResult:
	if not SCENES.has(scene_id) or not ContentDB.map.scenes.has(String(scene_id)):
		return MireTypes.failure(&"unknown_scene", &"That destination is not available.")
	var record: Dictionary = ContentDB.map.scenes[String(scene_id)]
	if not record.entrances.has(String(entrance_id)):
		return MireTypes.failure(&"unknown_entrance", &"That entrance is not available.")
	if scene_id == &"interior_undercroft" and not bool(candidate.flags.undercroft_open):
		return MireTypes.failure(&"story_locked", &"The undercroft is barred. Show Ada the charter and grain ledger first.")
	var yaw: float = float(ContentDB.map.exterior.entrance_yaws.get(String(entrance_id), 0)) if scene_id == &"exterior" else 0.0
	return MireTypes.success({"transform": Transform3D(Basis(Vector3.UP, yaw), _vector(record.entrances[String(entrance_id)]))})

func _begin(request: Dictionary) -> MireTypes.ActionResult:
	_operation = _next_id("travel")
	GameSession.travelling = true
	_prior_input = player.input_enabled
	if is_instance_valid(mode_controller):
		_prior_stack = mode_controller.snapshot_stack()
	else:
		_prior_stack = [&"gameplay"]
	player.set_input_enabled(false)
	if is_instance_valid(mode_controller):
		mode_controller.push_mode(&"travel")
	_run_transition.call_deferred(_operation, request)
	return MireTypes.success({"pending": true, "operation_id": String(_operation)})

func _run_transition(operation_id: StringName, request: Dictionary) -> void:
	await _fade_to(1)
	var token: StringName = request.get("prepared_token", &"")
	if token.is_empty():
		var prepared: MireTypes.ActionResult = await _prepare_world(request.scene_id, GameSession.snapshot())
		if not prepared.ok:
			await _finish(operation_id, request, prepared)
			return
		token = StringName(prepared.payload.prepared_token)
	var record: Dictionary = _prepared[token]
	var destination: Node3D = record.world
	var at: Transform3D = request.transform
	if request.has("entrance_id"):
		if not destination.get("entrances").has(request.entrance_id):
			discard_prepared(token)
			await _finish(operation_id, request, MireTypes.failure(&"unknown_entrance", &"The destination entrance is missing."))
			return
		at = destination.get("entrances")[request.entrance_id]
	var checked := validate_anchor(destination, at)
	if not checked.ok:
		discard_prepared(token)
		await _finish(operation_id, request, checked)
		return
	var old_world: Node3D = current_world
	var old_scene: StringName = loaded_scene_id
	if is_instance_valid(old_world):
		world_container.remove_child(old_world)
	record.viewport.remove_child(destination)
	world_container.add_child(destination)
	var synchronized: bool = await _wait_navigation(destination, at.origin)
	checked = validate_anchor(destination, at) if synchronized else MireTypes.failure(&"navigation_unavailable", &"Destination navigation did not synchronize.")
	if checked.ok and request.get("hazard", false):
		checked = _reset_detached_living(destination)
	if checked.ok:
		current_world = destination
		loaded_scene_id = request.scene_id
		checked = _commit_arrival(operation_id, request, record, at)
	if not checked.ok:
		world_container.remove_child(destination)
		record.viewport.add_child(destination)
		var restored_ready: bool = false
		if is_instance_valid(old_world):
			world_container.add_child(old_world)
			restored_ready = await _wait_navigation(old_world, player.global_position)
		current_world = old_world
		loaded_scene_id = old_scene
		if restored_ready:
			_attach_runtime(old_world)
			# Exit-tree cleanup also detached NPC/story listeners owned by GameRoot.
			world_activated.emit(old_world)
		discard_prepared(token)
		await _finish(operation_id, request, checked)
		return
	current_world = destination
	loaded_scene_id = request.scene_id
	_prepared.erase(token)
	record.viewport.free()
	if is_instance_valid(old_world):
		old_world.free()
	for node: Node in record.process_modes:
		node.process_mode = record.process_modes[node]
	destination.process_mode = Node.PROCESS_MODE_INHERIT
	_attach_runtime(destination)
	player.spawn_at(at.origin, at.basis.get_euler().y)
	last_safe[loaded_scene_id] = at
	_safe_elapsed = 0.0
	_hazard_retry_delay = 0.5
	var interactions := WorldInteractions.new()
	destination.add_child(interactions)
	interactions.configure(self, destination)
	world_activated.emit(destination)
	await _finish(operation_id, request, MireTypes.success({"scene_id": String(loaded_scene_id), "pending": false}))

func _commit_arrival(operation_id: StringName, request: Dictionary, record: Dictionary, at: Transform3D) -> MireTypes.ActionResult:
	if request.reason == &"load":
		var snapshot: Dictionary = record.snapshot.duplicate(true)
		snapshot.player.position = [at.origin.x, at.origin.y, at.origin.z]
		snapshot.player.yaw = at.basis.get_euler().y
		var restored: MireTypes.ActionResult = GameSession.restore(snapshot)
		GameSession.travelling = true
		return restored
	return GameSession.transactions.run(operation_id, func(candidate: Dictionary) -> MireTypes.ActionResult:
		candidate.player.scene_id = String(request.scene_id)
		candidate.player.position = [at.origin.x, at.origin.y, at.origin.z]
		candidate.player.yaw = at.basis.get_euler().y
		if request.get("hazard", false):
			candidate.player.health = maxf(1.0, float(candidate.player.health) - 10.0)
		return MireTypes.success({"scene_id": String(request.scene_id), "reason": String(request.reason)})
	)

func _prepare_world(scene_id: StringName, candidate: Dictionary) -> MireTypes.ActionResult:
	if not SCENES.has(scene_id) or not ResourceLoader.exists(SCENES[scene_id]):
		return MireTypes.failure(&"unknown_scene", &"The destination scene is unavailable.")
	var packed := load(SCENES[scene_id]) as PackedScene
	if packed == null:
		return MireTypes.failure(&"invalid_scene", &"The destination scene could not load.")
	var world := packed.instantiate() as Node3D
	if world == null:
		return MireTypes.failure(&"invalid_scene", &"The destination scene has no world root.")
	var viewport := SubViewport.new()
	viewport.name = "PreparedWorld"
	viewport.own_world_3d = true
	viewport.size = Vector2i(2, 2)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(world)
	var prepared := MireTypes.success()
	var process_modes: Dictionary = {}
	if world_builder.is_valid():
		var built: Variant = world_builder.call(world, candidate.duplicate(true))
		prepared = built if built is MireTypes.ActionResult else MireTypes.failure(&"invalid_runtime", &"World construction did not return a result.")
	if prepared.ok:
		for id: StringName in world.get("entities"):
			var entity: Node = world.get("entities")[id]
			if entity.has_method("apply_persistent_state"):
				var applied: Variant = entity.call("apply_persistent_state", candidate.world.get(String(id), {}).duplicate(true))
				if not applied is MireTypes.ActionResult or not applied.ok:
					prepared = MireTypes.failure(&"invalid_state", &"A saved world entity could not be restored.")
	if prepared.ok and world.get("entrances").is_empty():
		prepared = MireTypes.failure(&"unknown_entrance", &"The destination has no entrances.")
	if prepared.ok:
		# Disabled scripts must not remove staged geometry from the physics space.
		for node: Node in world.find_children("*", "", true, false):
			process_modes[node] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is CollisionObject3D:
				node.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		var first: Transform3D = world.get("entrances").values()[0]
		if not await _wait_navigation(world, first.origin):
			prepared = MireTypes.failure(&"navigation_unavailable", &"The destination navigation is unavailable.")
	if not prepared.ok:
		viewport.free()
		return prepared
	var token := _next_id("prepared")
	_prepared[token] = {"world": world, "viewport": viewport, "process_modes": process_modes}
	return MireTypes.success({"prepared_token": String(token)})

func _wait_navigation(world: Node3D, at: Vector3) -> bool:
	# Physics objects and region ownership must join the destination space, not just
	# retain an old ready flag from the detached preparation viewport.
	for frame: int in 120:
		await get_tree().physics_frame
		if not is_instance_valid(world) or not world.is_inside_tree():
			return false
		if frame >= 1 and _navigation_ready(world, at):
			return true
	return false

func _navigation_ready(world: Node3D, at: Vector3) -> bool:
	var map_rid: RID = world.get_world_3d().navigation_map
	if not map_rid.is_valid() or NavigationServer3D.map_get_iteration_id(map_rid) == 0:
		return false
	var owner_rid: RID = NavigationServer3D.map_get_closest_point_owner(map_rid, at)
	for region: NavigationRegion3D in world.get("navigation_regions"):
		if region.get_navigation_map() == map_rid and region.get_rid() == owner_rid and NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0:
			return NavigationServer3D.map_get_closest_point(map_rid, at).distance_to(at) < 0.65
	return false

func _finish(operation_id: StringName, request: Dictionary, result: MireTypes.ActionResult) -> void:
	await _fade_to(0)
	GameSession.travelling = false
	_operation = &""
	if request.get("recovery", false):
		GameSession.recovery.finish_pending_travel(operation_id, result)
	if is_instance_valid(mode_controller):
		if result.ok:
			mode_controller.push_mode(&"gameplay")
		else:
			var restored := mode_controller.restore_stack(_prior_stack)
			if not restored.ok:
				_record_diagnostic("Could not restore the prior menu stack: " + String(restored.message_key))
				mode_controller.push_mode(&"pause")
	else:
		player.set_input_enabled(_prior_input and not GameSession.recovery.has_pending_recovery())
	travel_completed.emit(operation_id, result)
	if result.ok and request.reason == &"travel":
		autosave_requested.emit(&"scene_transition")
	if not result.ok:
		_hazard_retry_delay = 2.0
		EventBus.feedback.emit(String(result.message_key))

func _fade_to(alpha: float) -> void:
	if not is_instance_valid(_fade):
		return
	if fade_seconds <= 0:
		_fade.color.a = alpha
		return
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade, "color:a", alpha, fade_seconds)
	await tween.finished

func _physics_process(delta: float) -> void:
	if not is_instance_valid(current_world) or not is_instance_valid(player) or not GameSession.active or GameSession.travelling or get_tree().paused or float(GameSession.state.player.health) <= 0:
		return
	_hazard_retry_delay = maxf(0, _hazard_retry_delay - delta)
	var reason := _hazard_reason(loaded_scene_id, player.global_position)
	if not reason.is_empty():
		if _hazard_retry_delay <= 0:
			recover_player(reason)
		return
	_safe_elapsed += delta
	if _safe_elapsed >= 0.5 and player.is_on_floor() and not GameSession.action_locked and not is_dangerous():
		_safe_elapsed = 0
		var grounded := Transform3D(Basis(Vector3.UP, player.rotation.y), player.global_position)
		var space := current_world.get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(grounded.origin + Vector3.UP * 0.2, grounded.origin - Vector3.UP * 0.4, MireTypes.WORLD))
		if not hit.is_empty():
			grounded.origin.y = hit.position.y
			if validate_anchor(current_world, grounded).ok:
				last_safe[loaded_scene_id] = grounded

func _hazard_at(scene_id: StringName, at: Vector3) -> bool:
	return not _hazard_reason(scene_id, at).is_empty()

func _hazard_reason(scene_id: StringName, at: Vector3) -> StringName:
	if not at.is_finite():
		return &"invalid_position"
	if scene_id != &"exterior":
		return &"bounds" if at.y < -6 or at.y > 15 or absf(at.x) > 30 or at.z > 20 or at.z < -70 else &""
	for row: Dictionary in ContentDB.map.exterior.hazards:
		if row.kind == "bounds":
			var low := _vector(row.minimum)
			var high := _vector(row.maximum)
			if at.x < low.x or at.x > high.x or at.y < low.y or at.y > high.y or at.z < low.z or at.z > high.z:
				return &"bounds"
		elif row.kind == "deep_water":
			var center := _vector(row.center)
			var offset := Vector2((at.x - center.x) / float(row.radii[0]), (at.z - center.z) / float(row.radii[1]))
			if offset.length_squared() <= 1.0 and at.y <= float(row.max_y):
				return &"deep_water"
	return &""

func _portal_overlap(scene_id: StringName, at: Vector3) -> bool:
	var portals: Array = ContentDB.map.exterior.portals if scene_id == &"exterior" else [{"position": [0, 0, 5.5], "size": [1.5, 2.5, 0.6]}]
	for row: Dictionary in portals:
		var center := _vector(row.position) + Vector3.UP * float(row.size[1]) / 2
		var size := _vector(row.size)
		if AABB(center - size / 2, size).grow(0.45).has_point(at + Vector3.UP * 0.9):
			return true
	return false

func _reset_detached_living(world: Node3D) -> MireTypes.ActionResult:
	for node: Node in world.find_children("*", "", true, false):
		if node is EnemyActor and not node.combat.dead:
			var reset: MireTypes.ActionResult = node.reset_living_encounter()
			if not reset.ok:
				return reset
	if world.has_method("reset_live_encounters"):
		var reset: Variant = world.call("reset_live_encounters")
		if not reset is MireTypes.ActionResult or not reset.ok:
			return MireTypes.failure(&"invalid_runtime", &"The live encounter could not reset safely.")
	return MireTypes.success()

func _attach_runtime(world: Node3D) -> void:
	for node: Node in world.find_children("*", "", true, false):
		if node is EncounterCoordinator:
			node.configure(player)
	for node: Node in world.find_children("*", "", true, false):
		if node is EnemyActor:
			node.player = player
			if is_instance_valid(node.coordinator):
				node.coordinator.register_enemy(node)

func _record_diagnostic(message: String) -> void:
	diagnostics.append(message)
	print("WORLD_RECOVERY " + message)
	diagnostic_recorded.emit(message)

func _next_id(kind: String) -> StringName:
	while true:
		_sequence += 1
		var id := StringName("world/%s/%d" % [kind, _sequence])
		if not GameSession.state.transactions.has(String(id)) and not _prepared.has(id):
			return id
	return &""

func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func _exit_tree() -> void:
	for token: StringName in _prepared.keys():
		discard_prepared(token)
	if not _operation.is_empty():
		GameSession.travelling = false
