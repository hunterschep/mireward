class_name NavigationArena
extends Node3D

signal navigation_ready

@export var populate: bool = true
var region: NavigationRegion3D
var obstacle: StaticBody3D
var player: MirePlayer
var coordinator: EncounterCoordinator
var modes: GameModeController
var _caption: Label

func _ready() -> void:
	if "--verify-navigation" in OS.get_cmdline_user_args():
		populate = false
	_build_geometry()
	_build_navigation()
	_wait_for_navigation()

func _build_geometry() -> void:
	var ground := _body("Ground", Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	ArtMesh.box(ground, "Floor", Vector3(40, 1, 40), Vector3.ZERO, "moss")
	obstacle = _body("Obstacle", Vector3(4, 3, 2), Vector3(0, 1.5, 0))
	var wall_art: Node3D = VisualFactory.building(&"wall")
	wall_art.scale = Vector3(4.0 / 7.2, 3.0 / 4.4, 2.0)
	wall_art.position.y = -1.5
	obstacle.add_child(wall_art)

func _body(body_name: String, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = at
	body.collision_layer = MireTypes.WORLD
	body.collision_mask = MireTypes.PLAYER | MireTypes.HOSTILE
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	return body

func _build_navigation() -> void:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.4
	mesh.agent_height = 1.8
	var xs: Array[float] = [-19.5, -2.5, 2.5, 19.5]
	var zs: Array[float] = [-19.5, -1.5, 1.5, 19.5]
	var vertices := PackedVector3Array()
	for z: float in zs:
		for x: float in xs:
			vertices.append(Vector3(x, 0, z))
	mesh.set_vertices(vertices)
	for row: int in 3:
		for column: int in 3:
			if row == 1 and column == 1:
				continue
			var corner: int = row * 4 + column
			mesh.add_polygon(PackedInt32Array([corner, corner + 1, corner + 5, corner + 4]))
	region = NavigationRegion3D.new()
	region.name = "NavigationRegion"
	region.navigation_mesh = mesh
	add_child(region)

func _wait_for_navigation() -> void:
	var map: RID = region.get_navigation_map()
	for frame: int in 120:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.region_get_iteration_id(region.get_rid()) > 0 and NavigationServer3D.map_get_closest_point_owner(map, Vector3(0, 0, 9)) == region.get_rid():
			if populate:
				_populate()
			navigation_ready.emit()
			if "--verify-navigation" in OS.get_cmdline_user_args():
				_verify_navigation()
			return
	push_error("Navigation arena did not synchronize within 120 physics frames.")
	if "--verify-navigation" in OS.get_cmdline_user_args():
		get_tree().quit(1)

func _populate() -> void:
	GameSession.new_game()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("a8b2aa")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d8ceb1")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.shadow_enabled = true
	add_child(sun)
	player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	player.spawn_at(Vector3(0, 0, 9))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_caption = Label.new()
	_caption.position = Vector2(22, 18)
	_caption.add_theme_color_override("font_color", Color("242b28"))
	_caption.text = "Navigation arena | %s: move forward | %s: light attack | %s: block | %s: pause\nThe wall blocks sight. Walk around either side to approach the four archetypes." % [InputBindings.label(&"move_forward"), InputBindings.label(&"attack_light"), InputBindings.label(&"block"), InputBindings.label(&"pause")]
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_caption)
	var modal := ModalHost.new()
	canvas.add_child(modal)
	modes = GameModeController.new()
	add_child(modes)
	modes.configure(player, modal)
	coordinator = EncounterCoordinator.new()
	add_child(coordinator)
	coordinator.configure(player)
	coordinator.danger_changed.connect(func(danger: bool) -> void: GameSession.danger = danger)
	player.combat.died.connect(func(_id: StringName) -> void: modes.push_mode(&"death"))
	var archetypes: Array[StringName] = [&"cutpurse", &"levy_spearman", &"deserter_raider", &"hollow_keeper"]
	var positions: Array[Vector3] = [Vector3(0, 0, -7), Vector3(-8, 0, -5), Vector3(8, 0, -5), Vector3(0, 0, -12)]
	for index: int in archetypes.size():
		var spawn: Dictionary = {}
		for row: Dictionary in ContentDB.map.spawns:
			if StringName(row.archetype) == archetypes[index]:
				spawn = row.duplicate(true)
				break
		if spawn.is_empty():
			push_error("Navigation fixture is missing a canonical %s spawn." % archetypes[index])
			return
		var at: Vector3 = positions[index]
		spawn.position = [at.x, at.y, at.z]
		var toward: Vector3 = player.global_position - at
		spawn.yaw = atan2(-toward.x, -toward.z)
		var enemy: EnemyActor = load("res://scenes/actors/enemy.tscn").instantiate()
		add_child(enemy)
		var result: MireTypes.ActionResult = enemy.configure(spawn, player, coordinator)
		if not result.ok:
			push_error("Navigation fixture spawn failed: %s" % result.message_key)
			enemy.queue_free()

func _verify_navigation() -> void:
	var map: RID = region.get_navigation_map()
	var route: PackedVector3Array = NavigationServer3D.map_get_path(map, Vector3(0, 0, 9), Vector3(0, 0, -9), true)
	var valid: bool = route.size() >= 4 and player == null and coordinator == null and modes == null and get_child_count() == 3
	var forbidden := AABB(Vector3(-2.4, -0.1, -1.4), Vector3(4.8, 0.2, 2.8))
	var space := get_world_3d().direct_space_state
	for index: int in range(1, route.size()):
		if forbidden.intersects_segment(route[index - 1], route[index]) != null:
			valid = false
		var ray := PhysicsRayQueryParameters3D.create(route[index - 1] + Vector3.UP, route[index] + Vector3.UP, MireTypes.WORLD)
		if not space.intersect_ray(ray).is_empty():
			valid = false
	var blocked_ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 9), Vector3(0, 1, -9), MireTypes.WORLD)
	var blocked: Dictionary = space.intersect_ray(blocked_ray)
	valid = valid and blocked.get("collider") == obstacle
	var points: Array = []
	for point: Vector3 in route:
		points.append([point.x, point.y, point.z])
	print("NAVIGATION_ARENA_RESULT " + JSON.stringify({"ok": valid, "map_iteration": NavigationServer3D.map_get_iteration_id(map), "route": points, "wall_blocks_direct_ray": not blocked.is_empty(), "geometry_only": player == null and get_child_count() == 3}))
	get_tree().quit(0 if valid else 1)
