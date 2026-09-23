extends RefCounted

func run(t: SceneTree) -> void:
	var session: Node = t.root.get_node("GameSession")
	session.new_game()
	var valley: MireExterior = load("res://scenes/world/exterior/exterior.tscn").instantiate()
	t.root.add_child(valley)
	for frame: int in 150:
		if valley.is_navigation_ready():
			break
		await t.physics_frame
	t.check(valley.is_navigation_ready(), "R05 region and map synchronize at the actual start anchor")
	t.check(valley.navigation_cache_current(), "R05 cached navigation matches the committed map fingerprint")
	t.check(valley.scene_id == &"exterior" and valley.entities.is_empty(), "R06 exterior contains no duplicate player or premature story entity")
	t.check(valley.landmarks.size() == 9 and valley.landmark_areas.size() == 9, "R05/R10 nine visible landmarks and discovery trigger regions")
	t.check(valley.entrances.size() == 4 and valley.rest_anchors.size() == 3, "R06 paired exterior entrances and authored rest anchors preserved")
	t.check(valley.objective_reservations.size() == 13 and valley.npc_reservations.size() == 8, "R05 authored quest container and NPC reservations complete")
	t.check(valley.decoration == ExteriorDecor.placements(valley.manifest), "R05 fixed-seed decorative generation repeats exactly")
	for row: Dictionary in valley.decoration:
		t.check(not ExteriorDecor.reserved(Vector2(row.position[0], row.position[2]), valley.manifest), "R05 decoration avoids authored corridors and stations")
	var nav_map: RID = valley.get_world_3d().navigation_map
	var start: Vector3 = valley.entrances[&"start"].origin
	t.check(valley.hazard_definitions.size() == 2 and ExteriorTerrain.height_at(-245, 260, valley.manifest) < -1, "R11 deep millpond and exterior bounds have authored hazard definitions")
	for side: int in [-1, 1]:
		for along_x: bool in [true, false]:
			var from := Vector3(side * 318, 70, 0) if along_x else Vector3(0, 70, side * 318)
			var to := Vector3(side * 325, 70, 0) if along_x else Vector3(0, 70, side * 325)
			var hit := valley.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, MireTypes.WORLD))
			t.check(not hit.is_empty(), "R11 perimeter has physical collision behind the visible ridge")
	for landmark: Dictionary in valley.manifest.landmarks:
		var target := ExteriorTerrain.vector(landmark.position)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, start, target, true)
		t.check(path.size() >= 2 and path[path.size() - 1].distance_to(target) < 1.0, "R05 reachable navigation to " + String(landmark.id))
		var visual: Node3D = valley.landmarks[StringName(landmark.id)]
		t.check(visual.global_position.distance_to(target) < 0.01, "R05 landmark root matches its canonical anchor")
	for route: Dictionary in valley.manifest.exterior.routes:
		for index: int in route.points.size() - 1:
			var from := ExteriorTerrain.vector(route.points[index])
			var to := ExteriorTerrain.vector(route.points[index + 1])
			var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true)
			t.check(path.size() >= 2 and path[path.size() - 1].distance_to(to) < 1, "R05 connected " + String(route.id) + " segment " + str(index))
	for portal: Dictionary in valley.portal_definitions:
		var back: Transform3D = valley.entrances[StringName(portal.return_entrance)]
		var center := ExteriorTerrain.vector(portal.position)
		t.check(back.origin.distance_to(center) - float(portal.size[2]) / 2 >= 1.5, "R06 return anchor clears " + String(portal.id) + " trigger")
	for route: Dictionary in valley.manifest.exterior.routes:
		if route.id not in ["western_bypass", "eastern_bypass"]:
			continue
		for index: int in route.points.size() - 1:
			var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, ExteriorTerrain.vector(route.points[index]), ExteriorTerrain.vector(route.points[index + 1]), true)
			for waypoint: Vector3 in path:
				t.check(Vector2(waypoint.x + 30, waypoint.z - 30).length() > 35, "R05 bypass route stays outside the checkpoint encounter")
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	player.set_physics_process(false)
	(player.get_node("Combat") as CombatComponent).input_driven = false
	await t.physics_frame
	for anchor: Transform3D in valley.entrances.values() + valley.rest_anchors.values():
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = (player.get_node("BodyShape") as CollisionShape3D).shape
		query.transform = Transform3D(Basis.IDENTITY, anchor.origin + Vector3(0, 0.98, 0))
		query.collision_mask = MireTypes.WORLD
		t.check(valley.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "R11 start/return/rest anchor has full player body clearance")
	await _walk_gate(t, player, Vector3(-30, 0, 30), Vector3(-30, 0, 17))
	await _walk_gate(t, player, Vector3(180, 0, -83), Vector3(180, 0, -96))
	await _walk_gate(t, player, Vector3(40, 0, -222), Vector3(40, 0, -238))
	Input.action_release(&"move_forward")
	player.free()
	valley.free()
	await t.physics_frame
	session.new_game()

func _walk_gate(t: SceneTree, player: MirePlayer, from: Vector3, to: Vector3) -> void:
	player.spawn_at(from)
	player.set_physics_process(true)
	Input.action_press(&"move_forward")
	var passed: bool = false
	for frame: int in 360:
		var direction := to - player.global_position
		direction.y = 0
		if direction.length() < 0.6:
			passed = true
			break
		player.rotation.y = atan2(-direction.x, -direction.z)
		await t.physics_frame
	Input.action_release(&"move_forward")
	player.set_physics_process(false)
	t.check(passed and player.global_position.y > -0.1, "R05 actual player walks collision-clear passage at " + str(from))

## Optional longer physical route proof, called by bake_world.gd --verify-walks.
func walk_all_routes(t: SceneTree, populated: bool = false) -> void:
	var session: Node = t.root.get_node("GameSession")
	session.new_game()
	var valley: MireExterior = load("res://scenes/world/exterior/exterior.tscn").instantiate()
	t.root.add_child(valley)
	await valley.navigation_synchronized
	var player: MirePlayer = load("res://scenes/player/player.tscn").instantiate()
	t.root.add_child(player)
	(player.get_node("Combat") as CombatComponent).input_driven = false
	if populated:
		var factory := CampaignWorld.new(player)
		t.check(factory.build(valley, session.snapshot()).ok, "T17 route fixture includes authored campaign collision")
		# Prepared adapters and AI stay inactive; this proves static route clearance.
		valley.get_node("CampaignPopulation").coordinator.set_physics_process(false)
	await t.physics_frame
	var original_ticks: int = Engine.physics_ticks_per_second
	var original_scale: float = Engine.time_scale
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 8
	var report: Array[Dictionary] = []
	var nav_map: RID = valley.get_world_3d().navigation_map
	var clearance := WorldRouter.new()
	for route: Dictionary in valley.manifest.exterior.routes:
		player.spawn_at(ExteriorTerrain.vector(route.points[0]))
		var start_ms: int = Time.get_ticks_msec()
		var distance: float = 0
		var passed: bool = true
		for index: int in range(1, route.points.size()):
			var goal := ExteriorTerrain.vector(route.points[index])
			var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, player.global_position, goal, true)
			if path.size() < 2:
				passed = false
				break
			for waypoint: Vector3 in path:
				var step_start: int = Time.get_ticks_msec()
				var detour := Vector3.INF
				var avoided: Array[int] = []
				Input.action_press(&"move_forward")
				while Vector2(player.global_position.x - waypoint.x, player.global_position.z - waypoint.z).length() > 0.7:
					var previous := player.global_position
					if detour.is_finite() and Vector2(previous.x - detour.x, previous.z - detour.z).length() < 0.4:
						detour = Vector3.INF
					if populated and not detour.is_finite():
						var contact: KinematicCollision3D = player.get_last_slide_collision()
						if contact != null and contact.get_collider() is EnemyActor and player.global_position.distance_to(contact.get_collider().global_position) < 2.0 and contact.get_collider_id() not in avoided:
							detour = _actor_detour(valley, player, contact.get_collider(), waypoint, clearance)
							avoided.append(contact.get_collider_id())
							print("ROUTE_SIDESTEP ", contact.get_collider().entity_id, " via ", detour)
					var delta := (detour if detour.is_finite() else waypoint) - previous
					player.rotation.y = atan2(-delta.x, -delta.z)
					await t.physics_frame
					distance += previous.distance_to(player.global_position)
					if Time.get_ticks_msec() - step_start > 15000 or player.global_position.y < -0.5:
						var collision: KinematicCollision3D = player.get_last_slide_collision()
						print("ROUTE_BLOCKED ", JSON.stringify({"route": route.id, "position": str(player.global_position), "waypoint": str(waypoint), "collider": str(collision.get_collider()) if collision != null else "none"}))
						passed = false
						break
				Input.action_release(&"move_forward")
				if not passed:
					break
			if not passed:
				break
		var row := {"route": String(route.id), "passed": passed, "walked_meters": snappedf(distance, 0.1), "wall_seconds": (Time.get_ticks_msec() - start_ms) / 1000.0, "physics_ticks": 120, "time_scale": 8, "normal_walk_speed": 4}
		if populated:
			row["population"] = "complete exterior, static AI; runtime doors/rest checked separately"
		report.append(row)
		print(JSON.stringify(row))
		t.check(passed, "R05 actual player traversal of " + String(route.id))
	Engine.physics_ticks_per_second = original_ticks
	Engine.time_scale = original_scale
	Input.action_release(&"move_forward")
	DirAccess.make_dir_recursive_absolute("res://tests/output/exterior")
	var file := FileAccess.open("res://tests/output/exterior/" + ("populated_route_walks.json" if populated else "route_walks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	player.free()
	valley.free()
	clearance.free()
	session.new_game()

func _actor_detour(world: MireExterior, player: MirePlayer, actor: EnemyActor, goal: Vector3, clearance: WorldRouter) -> Vector3:
	var direction := goal - player.global_position
	direction.y = 0
	direction = direction.normalized()
	var side := Vector3(-direction.z, 0, direction.x)
	for sign: float in [1, -1]:
		var at := actor.global_position + side * sign * 1.5 - direction * 0.8
		if clearance.validate_anchor(world, Transform3D(Basis.IDENTITY, at)).ok:
			return at
	return Vector3.INF
